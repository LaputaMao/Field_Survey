import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class TaskScreen extends StatefulWidget {
  @override
  _TaskScreenState createState() => _TaskScreenState();
}

class _TaskScreenState extends State<TaskScreen> {
  // 注意保持你的后端 IP 正确
  final String _baseUrl = 'http://10.0.2.2:9096/api/v1';
  List<dynamic> _tasks = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchTasks();
  }

  // 1. 获取任务列表
  Future<void> _fetchTasks() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('jwt_token');

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/user/my-tasks'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> resData = jsonDecode(response.body);
        setState(() {
          _tasks = resData['data'] ?? [];
          _isLoading = false;
        });
      } else {
        throw Exception("加载失败: ${response.statusCode}");
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('获取任务失败：$e')));
      }
      setState(() => _isLoading = false);
    }
  }

  // 2. 接收特定任务并拉取 GeoJSON 详情
  Future<void> _fetchTaskGeoJSON(Map<String, dynamic> task) async {
    // 弹出全屏加载圈，防止用户狂点
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) =>
          Center(child: CircularProgressIndicator(color: Colors.green)),
    );

    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('jwt_token');

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/user/tasks/${task['id']}/geojson'),
        headers: {'Authorization': 'Bearer $token'},
      );

      Navigator.pop(context); // 关掉加载圈

      if (response.statusCode == 200) {
        final Map<String, dynamic> geoJsonData = jsonDecode(
          response.body,
        )['data'];

        // 我们将列表信息和具体的地图数据一并打包，返回给地图页
        Navigator.pop(context, {'task_info': task, 'geojson': geoJsonData});
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('接收任务详情失败：${response.statusCode}')),
        );
      }
    } catch (e) {
      Navigator.pop(context); // 关掉加载圈
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('网络错误：$e')));
    }
  }

  // 辅助方法：把 "2026-03-20T19:48:59..." 截取为 "YYYY-MM-DD"
  String _formatDate(String isoString) {
    if (isoString.isEmpty) return "未知时间";
    try {
      DateTime dt = DateTime.parse(isoString);
      return "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}";
    } catch (e) {
      return isoString.split('T').first;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('任务大厅'), backgroundColor: Colors.green),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _tasks.length,
              itemBuilder: (context, index) {
                final task = _tasks[index];
                bool isUnread = !(task['is_read'] ?? true);

                return Card(
                  margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ListTile(
                    // 未读小红点
                    leading: isUnread
                        ? Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                          )
                        : Icon(Icons.assignment, color: Colors.grey),
                    title: Text(
                      '任务编号: ${task['id']}',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('状态: ${task['status']}'),
                        Text('派发时间: ${_formatDate(task['created_at'])}'),
                      ],
                    ),
                    trailing: Icon(Icons.download, color: Colors.green),
                    onTap: () => _fetchTaskGeoJSON(task), // 一键接收并拉取任务详情
                  ),
                );
              },
            ),
    );
  }
}
