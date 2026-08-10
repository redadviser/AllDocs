enum DocumentType { pdf, word, excel, presentation, image }

DocumentType documentTypeFromName(String? raw) {
  return switch (raw) {
    'word' => DocumentType.word,
    'excel' => DocumentType.excel,
    'presentation' => DocumentType.presentation,
    'image' => DocumentType.image,
    _ => DocumentType.pdf,
  };
}

DocumentType documentTypeFromFileName(String fileName) {
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.doc') ||
      lower.endsWith('.docx') ||
      lower.endsWith('.txt') ||
      lower.endsWith('.rtf') ||
      lower.endsWith('.odt')) {
    return DocumentType.word;
  }
  if (lower.endsWith('.xls') ||
      lower.endsWith('.xlsx') ||
      lower.endsWith('.csv') ||
      lower.endsWith('.ods')) {
    return DocumentType.excel;
  }
  if (lower.endsWith('.ppt') ||
      lower.endsWith('.pptx') ||
      lower.endsWith('.odp')) {
    return DocumentType.presentation;
  }
  if (lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.png') ||
      lower.endsWith('.heic') ||
      lower.endsWith('.webp')) {
    return DocumentType.image;
  }
  return DocumentType.pdf;
}
