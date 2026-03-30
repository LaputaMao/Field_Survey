import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:field_survey/config/api_config.dart';

class TaskScreen extends StatefulWidget {
  @override
  _TaskScreenState createState() => _TaskScreenState();
}

class _TaskScreenState extends State<TaskScreen> {
  // 注意保持你的后端 IP 正确
  final String _baseUrl = ApiConfig.baseUrl;
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

  // ============== 更新：接收任务并拉取所有详情 ==============
  Future<void> _fetchTaskDetail(Map<String, dynamic> task) async {
    showDialog(
      // 弹出加载圈
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          Center(child: CircularProgressIndicator(color: Colors.green)),
    );

    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('jwt_token');

    try {
      // 变动点 1：接口换成了 detail
      final response = await http.get(
        Uri.parse('$_baseUrl/user/tasks/${task['id']}/detail'),
        headers: {'Authorization': 'Bearer $token'},
      );

      Navigator.pop(context); // 关加载圈

      if (response.statusCode == 200) {
        // 变动点 2：直接将整个全新的 data 数据块传回给地图页
        final Map<String, dynamic> detailData = jsonDecode(
          response.body,
        )['data'];

        Navigator.pop(context, {
          'task_info': task,
          'detail_data': detailData,
          // 这里包含了 planned_geojson 和 actual_line_geoms
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('获取详情失败：${response.statusCode}')),
        );
      }
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('网络错误：$e')));
    }
  }

  // ============== 新增：提交完成任务 ==============
  Future<void> _completeTask(int taskId) async {
    bool confirm =
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text("确认上报完成?"),
            content: Text("完成后该任务将流转至后台审核，请确认已上传本次任务所有规划路线。"),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text("取消", style: TextStyle(color: Colors.grey)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text("确认提交", style: TextStyle(color: Colors.green)),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirm) return;

    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('jwt_token');

    try {
      final response = await http.put(
        Uri.parse('$_baseUrl/user/tasks/$taskId/complete'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已成功确认完成！', style: TextStyle(color: Colors.white)),
            backgroundColor: Colors.green,
          ),
        );
        // 成功后刷新列表
        setState(() => _isLoading = true);
        _fetchTasks();
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('完成失败: ${response.body}')));
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('网络异常：$e')));
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
              // itemBuilder: (context, index) {
              //   final task = _tasks[index];
              //   bool isUnread = !(task['is_read'] ?? true);
              //   // 判断任务是否已完成（防止重复提交）
              //   bool isCompleted = task['status'] == 'completed';
              //
              //   return Card(
              //     margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              //     child: InkWell(
              //       // 整张卡片可点击进入地图
              //       onTap: () => _fetchTaskDetail(task),
              //       child: Padding(
              //         padding: const EdgeInsets.all(12.0),
              //         child: Row(
              //           children: [
              //             if (isUnread)
              //               Container(
              //                 width: 10,
              //                 height: 10,
              //                 margin: EdgeInsets.only(right: 10),
              //                 decoration: BoxDecoration(
              //                   color: Colors.red,
              //                   shape: BoxShape.circle,
              //                 ),
              //               )
              //             else
              //               SizedBox(width: 20),
              //
              //             Expanded(
              //               child: Column(
              //                 crossAxisAlignment: CrossAxisAlignment.start,
              //                 children: [
              //                   Text(
              //                     '任务编号: ${task['id']}',
              //                     style: TextStyle(
              //                       fontWeight: FontWeight.bold,
              //                       fontSize: 16,
              //                     ),
              //                   ),
              //                   SizedBox(height: 6),
              //                   Text(
              //                     '派发时间: ${_formatDate(task['created_at'])}',
              //                     style: TextStyle(color: Colors.grey[600]),
              //                   ),
              //                   Text(
              //                     '状态: ${task['status']}',
              //                     style: TextStyle(
              //                       color: isCompleted
              //                           ? Colors.blue
              //                           : Colors.orange,
              //                     ),
              //                   ),
              //                 ],
              //               ),
              //             ),
              //
              //             // 右侧的提交完成按钮
              //             ElevatedButton.icon(
              //               style: ElevatedButton.styleFrom(
              //                 backgroundColor: isCompleted
              //                     ? Colors.grey[300]
              //                     : Colors.green,
              //                 foregroundColor: isCompleted
              //                     ? Colors.grey
              //                     : Colors.white,
              //                 elevation: 0,
              //               ),
              //               icon: Icon(
              //                 isCompleted ? Icons.check : Icons.upload,
              //               ),
              //               label: Text(isCompleted ? "已完成" : "确认完成"),
              //               onPressed: isCompleted
              //                   ? null
              //                   : () => _completeTask(task['id']),
              //             ),
              //           ],
              //         ),
              //       ),
              //     ),
              //   );
              // },
              itemBuilder: (context, index) {
                final task = _tasks[index];
                bool isUnread = !(task['is_read'] ?? true);
                bool isCompleted = task['status'] == 'completed';

                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // 1. 未读状态红点
                        if (isUnread)
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(right: 12),
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                          ),

                        // 2. 左侧：任务核心信息
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '任务编号: ${task['id']}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 17,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Icon(
                                    Icons.calendar_today,
                                    size: 14,
                                    color: Colors.grey[600],
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _formatDate(task['created_at']),
                                    style: TextStyle(color: Colors.grey[600]),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      (isCompleted
                                              ? Colors.blue
                                              : Colors.orange)
                                          .withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  isCompleted ? "已完成" : "进行中",
                                  style: TextStyle(
                                    color: isCompleted
                                        ? Colors.blue
                                        : Colors.orange,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // 3. 右侧：操作按钮组 (垂直排列)
                        const SizedBox(width: 10),
                        Column(
                          children: [
                            // 查看任务按钮
                            SizedBox(
                              width: 100,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue[700],
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                onPressed: () => _fetchTaskDetail(task),
                                child: const Text("查看任务"),
                              ),
                            ),
                            const SizedBox(height: 8),
                            // 确认完成按钮
                            SizedBox(
                              width: 100,
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(
                                    color: isCompleted
                                        ? Colors.grey
                                        : Colors.green,
                                  ),
                                  foregroundColor: isCompleted
                                      ? Colors.grey
                                      : Colors.green,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                onPressed: isCompleted
                                    ? null
                                    : () => _completeTask(task['id']),
                                child: Text(isCompleted ? "已上报" : "确认完成"),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
