enum DocumentType { pdf, word, excel, image }

DocumentType documentTypeFromName(String? raw) {
  return switch (raw) {
    'word' => DocumentType.word,
    'excel' => DocumentType.excel,
    'image' => DocumentType.image,
    _ => DocumentType.pdf,
  };
}

DocumentType documentTypeFromFileName(String fileName) {
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.doc') || lower.endsWith('.docx')) {
    return DocumentType.word;
  }
  if (lower.endsWith('.xls') || lower.endsWith('.xlsx')) {
    return DocumentType.excel;
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
