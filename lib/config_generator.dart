import 'dart:convert';

class ConfigGenerator {
  static String generateVless({
    required String uuid,
    required String path,
    required String ipAddress,
    required int port,
    required String hostSni,
    required String name,
    String security = 'tls',
    String type = 'ws',
  }) {
    String encodedPath = Uri.encodeComponent(path.isEmpty ? '/' : path);
    String cleanName = name.replaceAll(' ', '_');
    if (security == 'none') {
      return 'vless://$uuid@$ipAddress:$port?encryption=none&security=none&type=$type&host=$hostSni&sni=$hostSni&path=$encodedPath#$cleanName';
    } else {
      return 'vless://$uuid@$ipAddress:$port?encryption=none&security=tls&type=$type&host=$hostSni&sni=$hostSni&path=$encodedPath#$cleanName';
    }
  }

  static String generateTrojan({
    required String password,
    required String path,
    required String ipAddress,
    required int port,
    required String hostSni,
    required String name,
    String security = 'tls',
    String type = 'ws',
  }) {
    String encodedPath = Uri.encodeComponent(path.isEmpty ? '/' : path);
    String cleanName = name.replaceAll(' ', '_');
    return 'trojan://$password@$ipAddress:$port?allowInsecure=1&security=$security&type=$type&host=$hostSni&sni=$hostSni&path=$encodedPath#$cleanName';
  }

  static String generateVmess({
    required String uuid,
    required String path,
    required String ipAddress,
    required int port,
    required String hostSni,
    required String name,
    String security = 'tls',
    String type = 'ws',
  }) {
    Map<String, dynamic> vmessMap = {
      "v": "2",
      "ps": name,
      "add": ipAddress,
      "port": port.toString(),
      "id": uuid,
      "aid": "0",
      "scy": "auto",
      "net": type,
      "type": "none",
      "host": hostSni,
      "path": path.isEmpty ? '/' : path,
      "tls": security == 'tls' ? 'tls' : '',
      "sni": hostSni
    };
    String jsonString = jsonEncode(vmessMap);
    String base64Str = base64Encode(utf8.encode(jsonString));
    return 'vmess://$base64Str';
  }
}
