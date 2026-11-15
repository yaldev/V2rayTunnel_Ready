import 'package:flutter/material.dart';
import 'database_helper.dart';
import 'config_generator.dart';

class ServerListScreen extends StatefulWidget {
  const ServerListScreen({super.key});

  @override
  State<ServerListScreen> createState() => _ServerListScreenState();
}

class _ServerListScreenState extends State<ServerListScreen> {
  List<Map<String, dynamic>> _staticServers = [];
  Map<String, List<Map<String, dynamic>>> _groupedNetworks = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });
    try {
      List<Map<String, dynamic>> staticServers = await DatabaseHelper().getAllStaticServers();
      List<Map<String, dynamic>> networks = await DatabaseHelper().getAllNetworks();

      Map<String, List<Map<String, dynamic>>> grouped = {};
      for (var net in networks) {
        String country = net['country'] ?? 'Other';
        grouped.putIfAbsent(country, () => []).add(net);
      }

      if (!mounted) return;
      setState(() {
        _staticServers = staticServers;
        _groupedNetworks = grouped;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _onStaticServerClicked(Map<String, dynamic> server) async {
    String name = server['name'] ?? 'Static Server';
    String address = server['address'] ?? '';
    int port = server['port'] ?? 443;
    String uuid = server['uuid'] ?? '';
    String sni = server['sni'] ?? '';
    String path = server['path'] ?? '/';
    String protocol = server['protocol'] ?? 'VLESS';

    String vless = ConfigGenerator.generateVless(uuid: uuid, path: path, ipAddress: address, port: port, hostSni: sni, name: name);
    String trojan = ConfigGenerator.generateTrojan(password: uuid, path: path, ipAddress: address, port: port, hostSni: sni, name: name);
    String vmess = ConfigGenerator.generateVmess(uuid: uuid, path: path, ipAddress: address, port: port, hostSni: sni, name: name);

    print("==== GENERATED CONFIGS for Static Server: $name ====");
    print(vless);
    print(trojan);
    print(vmess);
    print("==================================================");

    if (!mounted) return;
    _showConfigDialog(name, vless, trojan, vmess);
  }

  Future<void> _onCustomNetworkClicked(Map<String, dynamic> network) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(
          color: Color(0xFF00BFFF),
        ),
      ),
    );

    try {
      final key = await DatabaseHelper().getFastestKey();
      if (!mounted) return;
      Navigator.pop(context); // Dismiss loading

      if (key == null || key['ip'] == null || (key['ip'] as String).isEmpty) {
        _showErrorDialog("No connection keys available. Please check your internet connection.");
        return;
      }

      String uuidOrPass = key['uuid_or_pass'] ?? '';
      String path = key['path'] ?? '/';
      String ipAddress = key['ip'] ?? '';
      int port = key['port'] ?? 443;
      String security = key['security'] ?? 'tls';
      String type = key['type'] ?? 'ws';

      String hostSni = network['host'] ?? '';
      String name = network['name'] ?? 'Server';

      String vless = ConfigGenerator.generateVless(uuid: uuidOrPass, path: path, ipAddress: ipAddress, port: port, hostSni: hostSni, name: name, security: security, type: type);
      String trojan = ConfigGenerator.generateTrojan(password: uuidOrPass, path: path, ipAddress: ipAddress, port: port, hostSni: hostSni, name: name, security: security, type: type);
      String vmess = ConfigGenerator.generateVmess(uuid: uuidOrPass, path: path, ipAddress: ipAddress, port: port, hostSni: hostSni, name: name, security: security, type: type);

      print("==== GENERATED CONFIGS for Custom Network: $name ====");
      print(vless);
      print(trojan);
      print(vmess);
      print("=====================================================");

      if (!mounted) return;
      _showConfigDialog(name, vless, trojan, vmess);
    } catch (e) {
      if (!mounted) return;
      if (Navigator.canPop(context)) {
        Navigator.pop(context); // Dismiss loading
      }
      _showErrorDialog("Error generating config: $e");
    }
  }

  void _showErrorDialog(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Error"),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  void _showConfigDialog(String name, String vless, String trojan, String vmess) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Configs Generated"),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Configs generated successfully for $name",
                style: const TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 16),
              const Text("VLESS:", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00BFFF))),
              SelectableText(vless, style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 12),
              const Text("Trojan:", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00BFFF))),
              SelectableText(trojan, style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 12),
              const Text("VMess:", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00BFFF))),
              SelectableText(vmess, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF00BFFF),
        title: const Text(
          "Select Country / Network",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF00BFFF),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                // Special Section: Global Premium (GCP)
                Card(
                  elevation: 2,
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ExpansionTile(
                    leading: const Icon(Icons.star, color: Colors.amber, size: 28),
                    title: const Text(
                      "🌍 Global Premium (GCP)",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    subtitle: const Text(
                      "High-speed built-in servers",
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                    children: _staticServers.map((server) {
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                        leading: const Icon(Icons.bolt, color: Color(0xFF00BFFF)),
                        title: Text(
                          server['name'] ?? '',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        subtitle: Text(
                          "Protocol: ${server['protocol']}",
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        trailing: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00BFFF),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: () => _onStaticServerClicked(server),
                          child: const Text("Connect", style: TextStyle(fontSize: 12)),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 8),

                // Country Groups
                ..._groupedNetworks.entries.map((entry) {
                  String country = entry.key;
                  List<Map<String, dynamic>> networks = entry.value;

                  return Card(
                    elevation: 2,
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ExpansionTile(
                      leading: const Icon(Icons.public, color: Color(0xFF00BFFF), size: 28),
                      title: Text(
                        country,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      subtitle: Text(
                        "${networks.length} network operators available",
                        style: const TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                      children: networks.map((network) {
                        String name = network['name'] ?? '';
                        String isp = network['isp'] ?? '';

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                          leading: const Icon(Icons.signal_cellular_alt, color: Color(0xFF00BFFF), size: 20),
                          title: Text(
                            name,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                          subtitle: Text(
                            "Operator: $isp",
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          trailing: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF00BFFF),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onPressed: () => _onCustomNetworkClicked(network),
                            child: const Text("Connect", style: TextStyle(fontSize: 12)),
                          ),
                        );
                      }).toList(),
                    ),
                  );
                }),
              ],
            ),
    );
  }
}
