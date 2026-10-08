// AllDocs in-app viewer. The Flutter side (OfficeDocumentView) loads this
// page, streams the file in as base64 chunks with AllDocs.append(), then
// calls AllDocs.render(kind, options). Results go back through the
// "AllDocsViewer" channel: "rendered" or "error:<message>".
(function () {
  'use strict';

  var parts = [];
  var total = 0;

  function post(message) {
    if (window.AllDocsViewer) window.AllDocsViewer.postMessage(message);
  }

  function loadScripts(sources) {
    return sources.reduce(function (previous, src) {
      return previous.then(function () {
        return new Promise(function (resolve, reject) {
          var script = document.createElement('script');
          script.src = src;
          script.onload = resolve;
          script.onerror = function () { reject(new Error('Could not load ' + src)); };
          document.head.appendChild(script);
        });
      });
    }, Promise.resolve());
  }

  function fileBuffer() {
    var bytes = new Uint8Array(total);
    var offset = 0;
    parts.forEach(function (part) { bytes.set(part, offset); offset += part.length; });
    parts = [];
    return bytes.buffer;
  }

  // Pages keep their real width (A4 is ~794px); zoom them down to fit the
  // phone. Pinch-zoom still works on top.
  function fitToWidth(element, contentWidth) {
    var available = window.innerWidth - 16;
    element.style.zoom = contentWidth > available ? available / contentWidth : 1;
  }

  function renderDocx(buffer, content) {
    return loadScripts(['lib/jszip.min.js', 'lib/docx-preview.min.js']).then(function () {
      return window.docx.renderAsync(buffer, content, null, {
        inWrapper: true,
        breakPages: true,
        ignoreLastRenderedPageBreak: true,
        useBase64URL: true,
        experimental: true,
      });
    }).then(function () {
      var wrapper = content.querySelector('.docx-wrapper') || content;
      var widest = 0;
      wrapper.querySelectorAll('section.docx').forEach(function (page) {
        widest = Math.max(widest, page.offsetWidth);
      });
      var fit = function () { fitToWidth(wrapper, widest); };
      fit();
      window.addEventListener('resize', fit);
    });
  }

  // pptx-preview gives up silently (zero slides) when [Content_Types].xml
  // lists a part the file doesn't contain — PowerPoint tolerates that, and
  // some exporters produce it. Drop those entries first.
  function withoutMissingParts(buffer) {
    return window.JSZip.loadAsync(buffer).then(function (zip) {
      var types = zip.file('[Content_Types].xml');
      if (!types) return buffer;
      return types.async('text').then(function (xml) {
        var cleaned = xml.replace(/<Override\b[^>]*PartName="\/([^"]+)"[^>]*\/>/g,
          function (entry, part) { return zip.file(part) ? entry : ''; });
        if (cleaned === xml) return buffer;
        zip.file('[Content_Types].xml', cleaned);
        return zip.generateAsync({ type: 'arraybuffer' });
      });
    });
  }

  function renderPptx(buffer, content, fixedWidth) {
    return loadScripts(['lib/jszip.min.js', 'lib/pptx-preview.umd.js']).then(function () {
      return withoutMissingParts(buffer);
    }).then(function (cleaned) {
      var width = fixedWidth || Math.max(240, window.innerWidth - 16);
      var previewer = window.pptxPreview.init(content, {
        width: width,
        height: Math.round(width * 9 / 16),
        mode: 'list',
      });
      return previewer.preview(cleaned);
    }).then(function (pptx) {
      // Nothing laid out: let the app fall back to the text.
      if (!pptx || !pptx.slides || pptx.slides.length === 0) {
        throw new Error('No slides could be read');
      }
    });
  }

  function renderSheet(buffer, content, forThumbnail) {
    return loadScripts(['lib/xlsx.full.min.js']).then(function () {
      var workbook = window.XLSX.read(buffer, { type: 'array', cellDates: true });
      var tabs = document.getElementById('tabs');
      var show = function (index) {
        var name = workbook.SheetNames[index];
        var sheet = document.createElement('div');
        sheet.className = 'sheet';
        // sheet_to_html escapes cell text.
        sheet.innerHTML = window.XLSX.utils.sheet_to_html(workbook.Sheets[name], {
          header: '', footer: '',
        });
        content.replaceChildren(sheet);
        Array.prototype.forEach.call(tabs.children, function (tab, i) {
          tab.className = i === index ? 'active' : '';
        });
      };
      if (workbook.SheetNames.length > 1 && !forThumbnail) {
        workbook.SheetNames.forEach(function (name, index) {
          var tab = document.createElement('button');
          tab.textContent = name;
          tab.addEventListener('click', function () { show(index); });
          tabs.appendChild(tab);
        });
        tabs.hidden = false;
      }
      show(0);
    });
  }

  // --- Thumbnails -------------------------------------------------------
  // The first page / slide / sheet, drawn at its real size in a hidden
  // container, then turned into a JPEG: the DOM is embedded in an SVG
  // <foreignObject> and painted on a canvas. An SVG image can't load
  // anything itself, so blob: images are inlined as data: URLs first.

  function toDataUrl(url) {
    return fetch(url).then(function (response) { return response.blob(); })
      .then(function (blob) {
        return new Promise(function (resolve) {
          var reader = new FileReader();
          reader.onload = function () { resolve(reader.result); };
          reader.onerror = function () { resolve(''); };
          reader.readAsDataURL(blob);
        });
      }).catch(function () { return ''; });
  }

  function inlineBlobUrls(root) {
    var jobs = [];
    root.querySelectorAll('img[src^="blob:"]').forEach(function (img) {
      jobs.push(toDataUrl(img.getAttribute('src')).then(function (data) {
        img.setAttribute('src', data);
      }));
    });
    root.querySelectorAll('image').forEach(function (image) {
      var href = image.getAttribute('href') || image.getAttribute('xlink:href') || '';
      if (href.indexOf('blob:') !== 0) return;
      jobs.push(toDataUrl(href).then(function (data) {
        image.setAttribute('href', data);
        image.removeAttribute('xlink:href');
      }));
    });
    root.querySelectorAll('[style*="blob:"]').forEach(function (element) {
      var style = element.getAttribute('style');
      var urls = style.match(/blob:[^)"']+/g) || [];
      jobs.push(Promise.all(urls.map(function (url) {
        return toDataUrl(url).then(function (data) { style = style.split(url).join(data); });
      })).then(function () { element.setAttribute('style', style); }));
    });
    return Promise.all(jobs);
  }

  // Inside the SVG nothing inherits from the page or viewer.css, so the
  // base font and the sheet's table look are restated here.
  var THUMBNAIL_CSS =
    '.thumb-box, .thumb-box * { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; }' +
    '.thumb-box .sheet table { border-collapse: collapse; color: #1f2328; font-size: 13px; }' +
    '.thumb-box .sheet td, .thumb-box .sheet th { border: 1px solid #d0d7de; padding: 4px 8px; white-space: nowrap; }' +
    '.thumb-box .sheet tr:first-child td { background: #f3f5f7; font-weight: 600; }';

  function rasterize(element, width, height, outWidth) {
    var box = document.createElement('div');
    box.setAttribute('xmlns', 'http://www.w3.org/1999/xhtml');
    box.className = 'thumb-box';
    box.style.cssText = 'width:' + width + 'px;height:' + height + 'px;overflow:hidden;background:#fff;margin:0;';
    var styles = document.createElement('style');
    // The document's own styles come after the base ones, so a font the
    // document names still wins when the phone has it.
    styles.textContent = THUMBNAIL_CSS + '\n' + Array.prototype.map.call(
      document.querySelectorAll('style'), function (s) { return s.textContent; }).join('\n');
    box.appendChild(styles);
    box.appendChild(element.cloneNode(true));
    var svg = '<svg xmlns="http://www.w3.org/2000/svg" width="' + width + '" height="' + height + '">' +
      '<foreignObject x="0" y="0" width="100%" height="100%">' +
      new XMLSerializer().serializeToString(box) + '</foreignObject></svg>';
    return new Promise(function (resolve, reject) {
      var image = new Image();
      image.onload = function () {
        try {
          var scale = outWidth / width;
          var canvas = document.createElement('canvas');
          canvas.width = Math.round(width * scale);
          canvas.height = Math.round(height * scale);
          var context = canvas.getContext('2d');
          context.fillStyle = '#fff';
          context.fillRect(0, 0, canvas.width, canvas.height);
          context.drawImage(image, 0, 0, canvas.width, canvas.height);
          resolve(canvas.toDataURL('image/jpeg', 0.82));
        } catch (error) { reject(error); }
      };
      image.onerror = function () { reject(new Error('Could not draw the page')); };
      image.src = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(svg);
    });
  }

  function thumbnailSource(kind, buffer, stage) {
    if (kind === 'docx') {
      return renderDocx(buffer, stage).then(function () {
        var page = stage.querySelector('section.docx');
        if (!page) throw new Error('No page');
        // Pages are rasterized at their own size, not zoomed to the phone.
        (stage.querySelector('.docx-wrapper') || stage).style.zoom = 1;
        return { element: page, width: page.offsetWidth, height: page.offsetHeight };
      });
    }
    if (kind === 'pptx') {
      return renderPptx(buffer, stage, 720).then(function () {
        var slide = stage.querySelector('.pptx-preview-slide-wrapper');
        if (!slide) throw new Error('No slide');
        return { element: slide, width: slide.offsetWidth, height: slide.offsetHeight };
      });
    }
    return renderSheet(buffer, stage, true).then(function () {
      var sheet = stage.querySelector('.sheet') || stage;
      var table = sheet.querySelector('table');
      // Frame the top-left of the sheet, about as wide as its table (so a
      // small table isn't lost in white), in the cards' portrait shape.
      var width = Math.min(480, Math.max(240, table ? table.offsetWidth : 480));
      return { element: sheet, width: width, height: Math.round(width * 4 / 3) };
    });
  }

  window.AllDocs = {
    thumbnail: function (kind, options) {
      var stage = document.createElement('div');
      stage.style.cssText = 'position:absolute;left:-100000px;top:0;background:#fff;';
      document.body.appendChild(stage);
      var outWidth = (options && options.width) || 360;
      thumbnailSource(kind, fileBuffer(), stage).then(function (source) {
        return inlineBlobUrls(source.element).then(function () {
          return rasterize(source.element, source.width, source.height, outWidth);
        });
      }).then(function (jpeg) {
        post('thumbnail:' + jpeg.slice(jpeg.indexOf(',') + 1));
      }).catch(function (error) {
        post('error:' + (error && error.message ? error.message : String(error)));
      }).then(function () { stage.remove(); });
    },
    append: function (base64) {
      var binary = atob(base64);
      var part = new Uint8Array(binary.length);
      for (var i = 0; i < binary.length; i++) part[i] = binary.charCodeAt(i);
      parts.push(part);
      total += part.length;
    },
    render: function (kind, options) {
      document.body.style.setProperty('--top', ((options && options.top) || 64) + 'px');
      var content = document.getElementById('content');
      var buffer = fileBuffer();
      var job = kind === 'docx' ? renderDocx(buffer, content)
        : kind === 'pptx' ? renderPptx(buffer, content)
        : renderSheet(buffer, content);
      job.then(function () {
        post('rendered');
      }).catch(function (error) {
        post('error:' + (error && error.message ? error.message : String(error)));
      });
    },
  };

  post('ready');
})();
