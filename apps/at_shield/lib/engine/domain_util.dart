/// Strip URL junk → bare hostname.
String normalizeDomain(String raw) {
  var s = raw.trim().toLowerCase();
  if (s.isEmpty) return s;

  // bare host without scheme
  if (!s.contains('://')) {
    // drop path/query if pasted as x.com/foo
    s = s.split('/').first;
  } else {
    try {
      final u = Uri.parse(s);
      s = u.host.isNotEmpty ? u.host : s;
    } catch (_) {
      s = s.replaceFirst(RegExp(r'^https?://'), '');
      s = s.split('/').first;
    }
  }

  s = s.split('@').last; // user@host
  s = s.split(':').first; // host:port
  if (s.startsWith('www.')) s = s.substring(4);
  return s;
}
