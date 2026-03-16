import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

class TaskScreen extends StatelessWidget {
  // 模拟从后端拉取到的任务列表数据 (包含解析好的GeoJSON规划线)
  final List<Map<String, dynamic>> _mockTasks = [
    {
      'id': 1,
      'title': '【紧急】南湖水质检测巡视路线',
      'status': '进行中',
      // 二管规划的路线线段
      'route': [
        LatLng(30.2741, 120.1551),
        LatLng(30.2780, 120.1580),
        LatLng(30.2820, 120.1600),
      ],
      // 用户已经在路线上采集过的点位(已传云端)
      'points': [
        {
          'location': LatLng(30.2741, 120.1551),
          'desc': '水草丰茂，可见少量垃圾漂浮。',
          'photos': ['https://picsum.photos/200', 'https://picsum.photos/201'],
        },
      ],
    },
    {
      'id': 2,
      'title': '【常规】西山植被样方调查',
      'status': '未开始',
      'route': [LatLng(30.2500, 120.1400), LatLng(30.2550, 120.1450)],
      'points': [],
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('任务大厅'), backgroundColor: Colors.green),
      body: ListView.builder(
        itemCount: _mockTasks.length,
        itemBuilder: (context, index) {
          final task = _mockTasks[index];
          return Card(
            margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ListTile(
              leading: Icon(
                Icons.assignment_turned_in,
                color: task['status'] == '进行中' ? Colors.green : Colors.grey,
                size: 40,
              ),
              title: Text(
                task['title'],
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                "当前状态: ${task['status']} | 计划打点数: ${task['route'].length}",
              ),
              trailing: Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () {
                // ⭐ 核心逻辑：点击该任务，带着该任务的路线和点位数据，返回到上一级(HomeScreen)
                Navigator.pop(context, task);
              },
            ),
          );
        },
      ),
    );
  }
}
