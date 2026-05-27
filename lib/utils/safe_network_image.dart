/// Helpers to avoid loading non-image URLs (e.g. HTML error pages) as images.
library;

/// Returns true when [url] looks like a remote image the app should request.
bool isValidNetworkImageUrl(String? url) {
  if (url == null) return false;
  final u = url.trim();
  if (u.isEmpty || u == 'local_storage') return false;
  if (!u.startsWith('http://') && !u.startsWith('https://')) return false;

  final lower = u.toLowerCase();
  if (lower.startsWith('data:text/html') || lower.contains('.html')) {
    return false;
  }

  if (lower.contains('firebasestorage.googleapis.com') ||
      lower.contains('googleusercontent.com') ||
      lower.contains('storage.googleapis.com')) {
    return true;
  }

  const exts = ['.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp', '.heic'];
  for (final ext in exts) {
    if (lower.contains(ext)) return true;
  }

  if (lower.contains('alt=media') || lower.contains('/o/')) return true;

  return false;
}
