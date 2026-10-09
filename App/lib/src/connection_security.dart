// ESP32 HTTP is intended for a trusted local network. Public servers need TLS.
bool isLocalNetworkHost(String host) {
  host = host.toLowerCase().replaceAll('[', '').replaceAll(']', '');
  if (host == 'localhost' || host.endsWith('.local') || host == '::1') {
    return true;
  }
  if (host.contains(':')) {
    return host.startsWith('fc') ||
        host.startsWith('fd') ||
        RegExp(r'^fe[89ab][0-9a-f]:').hasMatch(host);
  }
  final parts = host.split('.');
  if (parts.length != 4) return false;
  final octets = parts.map(int.tryParse).toList();
  if (octets.any((value) => value == null || value < 0 || value > 255)) {
    return false;
  }
  return octets[0] == 10 ||
      octets[0] == 127 ||
      (octets[0] == 172 && octets[1]! >= 16 && octets[1]! <= 31) ||
      (octets[0] == 192 && octets[1] == 168) ||
      (octets[0] == 169 && octets[1] == 254);
}
