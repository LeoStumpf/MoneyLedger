/// Non-web: files are saved through the system save dialog instead.
Future<void> downloadFile(String fileName, List<int> bytes, String mimeType) =>
    throw UnsupportedError('browser download is web-only');
