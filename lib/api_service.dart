import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'database_helper.dart';

class ApiService {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));
  final DatabaseHelper _dbHelper = DatabaseHelper();

  final List<String> serversUrls = [
    'https://raw.githubusercontent.com/0xRadikal/Free-v2ray-Configs/main/verified/configs_base64.txt',
    'https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/All_Configs_base64_Sub.txt',
    'https://raw.githubusercontent.com/barry-far/V2ray-Configs/main/All_Configs_base64_Sub.txt',
    'https://raw.githubusercontent.com/MhdiTaheri/V2rayCollector/main/sub/mix_base64.txt',
    'https://raw.githubusercontent.com/mahdibland/V2RayAggregator/master/sub/sub_merge_base64.txt'
  ];

  Future<void> loadNetworks() async {
    try {
      String jsonString = await rootBundle.loadString('assets/networks.json');
      final Map<String, dynamic> data = jsonDecode(jsonString);
      final List<dynamic> networks = data['networks'] ?? [];

      for (var network in networks) {
        await _dbHelper.insertNetwork({
          'country': network['country'] ?? '',
          'isp': network['isp'] ?? '',
          'name': network['name'] ?? '',
          'host': network['host'] ?? '',
        });
      }
      print('Networks loaded successfully from assets.');
    } catch (e) {
      print('Error loading networks from assets: $e');
    }
  }

  Future<void> loadStaticServers() async {
    try {
      String jsonString = await rootBundle.loadString('assets/static_servers.json');
      final List<dynamic> servers = jsonDecode(jsonString);

      for (var server in servers) {
        await _dbHelper.insertStaticServer({
          'name': server['name'] ?? '',
          'address': server['address'] ?? '',
          'port': server['port'] ?? 443,
          'protocol': server['protocol'] ?? 'VLESS',
          'uuid': server['uuid'] ?? '',
          'sni': server['sni'] ?? '',
          'host': server['host'] ?? '',
          'path': server['path'] ?? '/',
        });
      }
      print('Static servers loaded successfully from assets.');
    } catch (e) {
      print('Error loading static servers from assets: $e');
    }
  }

  Future<void> fetchKeysFromGitHub() async {
    try {
      await _dbHelper.clearKeys();
      int totalCount = 0;

      for (String url in serversUrls) {
        try {
          final response = await _dio.get(url);

          if (response.statusCode == 200 && response.data != null) {
            String base64Content = response.data.toString().trim();
            if (base64Content.isEmpty) continue;

            String decodedString = base64Content;
            try {
              decodedString = utf8.decode(base64Decode(base64Content));
            } catch (_) {
              // Fallback to raw text if not base64
            }

            List<String> lines = decodedString.split('\n');

            for (var line in lines) {
              line = line.trim();
              if (line.isEmpty) continue;

              if (line.startsWith('vless://') || line.startsWith('trojan://') || line.startsWith('vmess://')) {
                try {
                  String protocol = 'vless';
                  if (line.startsWith('trojan://')) protocol = 'trojan';
                  if (line.startsWith('vmess://')) protocol = 'vmess';

                  if (protocol == 'vmess') {
                    try {
                      String vmessBase64 = line.substring(8);
                      String normalized = vmessBase64.trim();
                      while (normalized.length % 4 != 0) {
                        normalized += '=';
                      }
                      String jsonStr = utf8.decode(base64Decode(normalized));
                      Map<String, dynamic> vmessMap = jsonDecode(jsonStr);
                      String uuid = vmessMap['id'] ?? '';
                      String ip = vmessMap['add'] ?? '';
                      String path = vmessMap['path'] ?? '/';
                      int port = int.tryParse(vmessMap['port']?.toString() ?? '443') ?? 443;
                      String net = vmessMap['net'] ?? 'ws';
                      String tls = vmessMap['tls'] ?? '';
                      String security = tls == 'tls' ? 'tls' : 'none';
                      if (port == 80) security = 'none';
                      String hostHeader = vmessMap['host'] ?? vmessMap['sni'] ?? '';

                      if (ip.isNotEmpty && uuid.isNotEmpty) {
                        await _dbHelper.insertKey({
                          'uuid_or_pass': uuid,
                          'path': path,
                          'protocol': 'vmess',
                          'ip': ip,
                          'port': port,
                          'security': security,
                          'type': net,
                          'host_header': hostHeader,
                          'ping_ms': totalCount * 2,
                        });
                        totalCount++;
                      }
                    } catch (_) {}
                    continue;
                  }

                  String withoutProtocol = line.substring(protocol.length + 3);

                  int atIndex = withoutProtocol.indexOf('@');
                  if (atIndex == -1) continue;

                  String uuidOrPass = withoutProtocol.substring(0, atIndex);
                  String remainder = withoutProtocol.substring(atIndex + 1);

                  int qIndex = remainder.indexOf('?');
                  int hIndex = remainder.indexOf('#');
                  int addressEnd = remainder.length;
                  if (qIndex != -1 && qIndex < addressEnd) addressEnd = qIndex;
                  if (hIndex != -1 && hIndex < addressEnd) addressEnd = hIndex;

                  String addressPart = remainder.substring(0, addressEnd);
                  String ip = addressPart;
                  int port = 443;

                  int colonIndex = addressPart.lastIndexOf(':');
                  if (colonIndex != -1) {
                    ip = addressPart.substring(0, colonIndex);
                    String portStr = addressPart.substring(colonIndex + 1);
                    port = int.tryParse(portStr) ?? 443;
                  }

                  String security = 'tls';
                  String type = 'ws';
                  String hostHeader = '';
                  String path = '/';

                  try {
                    Uri uri = Uri.parse(line);
                    if (uri.hasQuery) {
                      security = uri.queryParameters['security'] ?? (uri.queryParameters['tls'] == 'tls' ? 'tls' : 'tls');
                      type = uri.queryParameters['type'] ?? uri.queryParameters['net'] ?? 'ws';
                      hostHeader = uri.queryParameters['host'] ?? uri.queryParameters['sni'] ?? '';
                      String? qPath = uri.queryParameters['path'];
                      if (qPath != null && qPath.isNotEmpty) {
                        path = Uri.decodeComponent(qPath);
                      }
                    }
                  } catch (_) {
                    int qIdx = remainder.indexOf('?');
                    if (qIdx != -1) {
                      String queryStr = remainder.substring(qIdx + 1);
                      int hIdx = queryStr.indexOf('#');
                      if (hIdx != -1) queryStr = queryStr.substring(0, hIdx);
                      List<String> params = queryStr.split('&');
                      for (var param in params) {
                        List<String> kv = param.split('=');
                        if (kv.length == 2) {
                          if (kv[0] == 'path') path = Uri.decodeComponent(kv[1]);
                          if (kv[0] == 'security' || kv[0] == 'tls') security = kv[1];
                          if (kv[0] == 'type' || kv[0] == 'net') type = kv[1];
                          if (kv[0] == 'host' || kv[0] == 'sni') hostHeader = kv[1];
                        }
                      }
                    }
                  }

                  if (port == 80 && security == 'tls') {
                    security = 'none';
                  }

                  if (ip.isNotEmpty) {
                    await _dbHelper.insertKey({
                      'uuid_or_pass': uuidOrPass,
                      'path': path,
                      'protocol': protocol,
                      'ip': ip,
                      'port': port,
                      'security': security,
                      'type': type,
                      'host_header': hostHeader,
                      'ping_ms': totalCount * 2,
                    });
                    totalCount++;
                  }
                } catch (e) {
                  // Skip malformed line
                }
              }
            }
          }
        } catch (e) {
          print('Failed to fetch from $url: $e');
        }
      }

      print('Total keys fetched from all repositories: $totalCount');
    } catch (e) {
      print('Error in fetchKeysFromGitHub: $e');
    }
  }
}
