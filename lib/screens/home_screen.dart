import 'dart:async';
import 'dart:io';
import 'package:field_survey/screens/task_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dotted_border/dotted_border.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/hold_to_complete_button.dart'; // 引入咱们刚写的长按按钮
import 'package:coordtransform/coordtransform.dart' as coordtransform;
import 'login_screen.dart'; // 引入你的登录页面
import 'field_survey_form_page.dart';
import 'package:field_survey/config/api_config.dart';
import 'package:dio/dio.dart';

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

// 1. 新增两个实体类，用于存储解析出的线和点以及它们的 properties（把它放在 _HomeScreenState 类的上面）
class TaskLine {
  final List<LatLng> points;
  final Map<String, dynamic> properties;

  TaskLine({required this.points, required this.properties});
}

class TaskPoint {
  final LatLng location;
  final Map<String, dynamic> properties;

  TaskPoint({required this.location, required this.properties});
}

class _HomeScreenState extends State<HomeScreen> {
  final MapController _mapController = MapController();

  // 右上角打开侧边栏的 Key
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  String _currentTaskTitle = "请从右侧菜单选择任务";

  // 2. 在 _HomeScreenState 内部，新增两个列表存放解析后的数据
  List<TaskLine> _taskLines = [];
  List<TaskPoint> _taskPoints = [];

  // 新增：存放从后端拉下来的该任务曾经走过的真实轨迹（历史轨）
  List<List<LatLng>> _historyActualRoutes = [];

  // 新增：记录当前用户选中的线路
  TaskLine? _selectedLine;


  // 路线与点位存储
  List<LatLng> _actualRoute = []; // 实际走过的绿色轨迹
  List<Map<String, dynamic>> _actualPoints = []; // 实际打的点

  // 状态控制
  bool _isSurveying = false; // 是否在调查中
  LatLng? _currentLocation; // 手机实时GPS位置
  StreamSubscription<Position>? _positionStream; // 轨迹监听流
  // --- 新增：任务与时间上下文 ---
  int? _currentTaskId;           // 当前进行中的大任务ID
  DateTime? _surveyStartTime;    // 任务开始时间
  final String _baseUrl = ApiConfig.baseUrl; // 换成真实的后端地址

  @override
  void initState() {
    super.initState();
    // 页面初始化时，尝试获取一次当前位置并自动跳转
    _initCurrentLocation();
  }

  // ================= 退出登录逻辑：弹窗提示 =================
  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange),
              SizedBox(width: 8),
              Text('退出登录'),
            ],
          ),
          content: Text(
            _isSurveying
                ? '您当前正在执行调查任务！此时退出登录将丢失所有未上传的轨迹和点位数据，确定要退出吗？'
                : '确定要退出当前账号吗？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(), // 关闭弹窗
              child: Text('取消', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () async {
                Navigator.of(context).pop(); // 先关闭弹窗
                await _performLogout(); // 执行彻底清理
              },
              child: Text('确定退出', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  // ================= 退出登录逻辑：清理与跳转 =================
  Future<void> _performLogout() async {
    // 1. 关闭可能正在运行的 GPS 监听流，防止内存泄漏和后台异常崩溃
    _positionStream?.cancel();

    // 2. 清理 SharedPreferences 中的 Token 和其他用户信息
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove('jwt_token');
    // 如果你本地还存了诸如 user_id, 角色等也可以一并 remove:
    // await prefs.remove('user_id');

    // 3. 销毁当前所有的路由栈，并把 LoginScreen 作为新的唯一根节点
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => LoginScreen()),
        (Route<dynamic> route) => false, // return false 表示连根拔起，统统销毁
      );
    }
  }

  // ============== 新增逻辑：进入地图自动定位 ==============
  Future<void> _initCurrentLocation() async {
    // 1. 检查手机 GPS 服务是否开启
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // 如果没开GPS，就保持默认视图(不跳转)
      return;
    }

    // 2. 检查应用是否拥有定位权限
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return; // 用户拒绝权限，保持默认视图
      }
    }

    try {
      // 3. 获取当前最新的单签位置 (并非持续追踪)
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: Duration(seconds: 5), // 给定一个超时时间，防止卡死
      );

      // 4. 更新坐标并平滑移动地图视角
      if (mounted) {
        setState(() {
          _currentLocation = LatLng(position.latitude, position.longitude);
        });

        // 将地图中心点移动到用户的实际位置，缩放级别设为 16.0
        _mapController.move(_currentLocation!, 16.0);
      }
    } catch (e) {
      debugPrint("初始定位获取失败: $e");
    }
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    super.dispose();
  }

  // --- 新增：GPS(WGS84) 转 高德(GCJ-02) ---
  LatLng _wgsToGcj(LatLng wgs84) {
    // coordtransform 格式：[lon, lat]
    // todo 修改成 GCJ02
    // todo 注意! 模拟器中的GPS(小蓝点,绿色轨迹都没有转wgs84,因为好像模拟器就是GCJ02),后续记得统一
    final gcjList = coordtransform.CoordTransform.transformWGS84toGCJ02(
      wgs84.longitude,
      wgs84.latitude,
    );
    return LatLng(gcjList.lat, gcjList.lon); // 转回 LatLng(lat, lon)
    return wgs84;
  }

  // (可选拓展) 高德(GCJ-02) 转 GPS(WGS84)，比如想把地图点击获取的坐标反转存库时用
  LatLng _gcjToWgs(LatLng gcj02) {
    final wgsList = coordtransform.CoordTransform.transformGCJ02toWGS84(
      gcj02.longitude,
      gcj02.latitude,
    );
    return LatLng(wgsList.lat, wgsList.lon);
  }

  // 3. 重写 _loadTaskToMap 方法处理 GeoJSON
  void _loadTaskToMap(Map<String, dynamic> result) {
    final taskInfo = result['task_info'];
    final detailData = result['detail_data']; // 拿到新的整块 data
    // ⭐ 记录当前的 Task ID 备用
    _currentTaskId = taskInfo['id'];
    // 准备容器
    List<TaskLine> parsedLines = [];
    List<TaskPoint> parsedPoints = [];
    List<List<LatLng>> parsedHistoryRoutes = [];
    List<LatLng> allCoordinatesForBounding = []; // 用于视角缩放(包含WGS84)

    // 1. 解析规划图层 planned_geojson
    final plannedGeojson = detailData['planned_geojson'];
    if (plannedGeojson != null &&
        plannedGeojson['type'] == 'FeatureCollection' &&
        plannedGeojson['features'] != null) {
      for (var feature in plannedGeojson['features']) {
        final geometry = feature['geometry'];
        final properties = feature['properties'] ?? {};

        if (geometry['type'] == 'LineString') {
          List<LatLng> lineCoords = [];
          for (var coord in geometry['coordinates']) {
            LatLng ll = LatLng(coord[1], coord[0]); // [lon, lat] 转 LatLng
            lineCoords.add(ll);
            allCoordinatesForBounding.add(ll);
          }
          parsedLines.add(TaskLine(points: lineCoords, properties: properties));
        } else if (geometry['type'] == 'Point') {
          var coord = geometry['coordinates'];
          LatLng ll = LatLng(coord[1], coord[0]);
          parsedPoints.add(TaskPoint(location: ll, properties: properties));
          allCoordinatesForBounding.add(ll);
        }
      }
    }

    // 2. 解析实际轨迹图层 actual_line_geoms (新增)
    final actualGeoms = detailData['actual_line_geoms'];
    if (actualGeoms != null && actualGeoms is List) {
      for (var feature in actualGeoms) {
        if (feature['type'] == 'Feature' &&
            feature['geometry']['type'] == 'LineString') {
          List<LatLng> actCoords = [];
          for (var coord in feature['geometry']['coordinates']) {
            LatLng ll = LatLng(coord[1], coord[0]);
            actCoords.add(ll);
            allCoordinatesForBounding.add(ll); // 缩放视野时也要把人走过的地方包进去
          }
          parsedHistoryRoutes.add(actCoords);
        }
      }
    }

    setState(() {
      _taskLines = parsedLines;
      _taskPoints = parsedPoints;
      _historyActualRoutes = parsedHistoryRoutes; // 保存历史轨迹
      _currentTaskTitle =
          "任务: #${taskInfo['id']} (${detailData['task_status']})";
      _selectedLine = null; // 重置选中状态
    });

    // ========== 视角自动缩放 (需使用 WGS转GCJ) ==========
    if (allCoordinatesForBounding.isNotEmpty) {
      final gcjBoundsCoordinates = allCoordinatesForBounding
          .map((p) => _wgsToGcj(p))
          // .map((p) => p)
          .toList();
      final bounds = LatLngBounds.fromPoints(gcjBoundsCoordinates);

      _mapController.fitCamera(
        CameraFit.bounds(bounds: bounds, padding: EdgeInsets.all(50.0)),
      );
    }
  }

  // 4. 重写显示 Properties 弹窗的方法
  void _showPropertiesSheet(Map<String, dynamic> properties, String type) {
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "[$type] 详情信息",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 15),
              // 动态遍历 properties 里的所有键值对并展示
              ...properties.entries
                  .map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Text(
                        "${entry.key}: ${entry.value}",
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  )
                  .toList(),
              SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  // ============== 开始调查与结束调查 ==============
  Future<void> _startSurvey() async {
    // 1. 请求定位权限
    LocationPermission permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("需要GPS权限才能开始定位打卡")));
      return;
    }

    setState(() {
      _isSurveying = true;
      _actualRoute.clear();
      _actualPoints.clear();
      // _surveyStartTime = DateTime.now().toUtc();
      _surveyStartTime = DateTime.now();
    });

    // 2. 开启位置实时监听
    _positionStream =
        Geolocator.getPositionStream(
          locationSettings: LocationSettings(
            accuracy: LocationAccuracy.best,
            distanceFilter: 2,
          ), // 移动2米更新一次
        ).listen((Position position) {
          setState(() {
            _currentLocation = LatLng(position.latitude, position.longitude);
            _actualRoute.add(_currentLocation!); // 压入绿色轨迹点
            _mapController.move(_wgsToGcj(_currentLocation!), 16.0); // 视角跟随移动
          });
        });
  }

  Future<void> _endSurvey() async {
    // 1. 停止监听 GPS 定位
    _positionStream?.cancel();

    // 防止空指针的保险拦截
    if (_currentTaskId == null || _selectedLine == null || _surveyStartTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("缺少必要任务数据，无法上传")));
      return;
    }

    // 弹出加载动画
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(child: CircularProgressIndicator(color: Colors.green)),
    );

    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString('jwt_token');

      // 2. 组装符合规范的 GeoJSON LineString
      // 将 List<LatLng> 转换为后端的 [[lon, lat], [lon, lat]...] 格式
      List<List<double>> coordinates = _actualRoute.map((point) {
        return [point.longitude, point.latitude];
      }).toList();

      // 获取当前线的标识 (适配后端 path_id：假设 properties 存了'线路号')
      String pathId = _selectedLine!.properties['线路号'] ?? _selectedLine!.properties['Id'] ?? "unknown_path";

      // 3. 构建发送给后端的 payload
      Map<String, dynamic> payload = {
        "task_id": _currentTaskId,
        "path_id": pathId,
        "actual_line_geom": {
          "type": "Feature",
          "geometry": {
            "type": "LineString",
            "coordinates": coordinates // 标准的 WGS84 经纬度数组
          },
          "properties": {} // 甲方暂时没要求属性可以给空
        },
        "start_time": _surveyStartTime!.toIso8601String(), // 例如 "2023-11-01T08:00:00.000Z"
        // "end_time": DateTime.now().toUtc().toIso8601String(),
        "end_time": DateTime.now().toIso8601String(),
      };

      // 4. 发起网络请求
      var dio = Dio();
      var response = await dio.post(
        "$_baseUrl/user/routes/upload",
        data: payload,
        options: Options(headers: {"Authorization": "Bearer $token"}),
      );

      Navigator.pop(context); // 关闭加载圈

      if (response.statusCode == 200 || response.statusCode == 201) {
        // ⭐ 获取后端的 message 并展示
        String msg = response.data['message'] ?? '轨迹上传成功';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg, style: TextStyle(fontWeight: FontWeight.bold)), backgroundColor: Colors.green));

        // 上传完清空视图
        setState(() {
          _isSurveying = false;
          _selectedLine = null; // 释放绑定的路线
          _actualRoute.clear();
          _actualPoints.clear();
          _currentLocation = null;
          _initCurrentLocation();
        });

      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('上传失败：${response.statusCode}')));
      }

    } catch (e) {
      Navigator.pop(context); // 关闭加载圈
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('轨迹上传异常：$e')));
    }
  }


  void _openSurveyForm({
    Map<String, dynamic>? existingPoint,
    int? pointIndex,
  }) async {
    if (_currentLocation == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("GPS信号弱，无法进行打点")));
      return;
    }

    // 需求2：点击打点后，先弹出模板选择器
    final String? selectedTemplate = await showModalBottomSheet<String>(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  "请选择数据填报模板",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              Divider(height: 1),
              ListTile(
                leading: Icon(Icons.assignment, color: Colors.green),
                title: Text('生态地质调查点记录表'),
                onTap: () => Navigator.pop(context, '1'), // 传回代号1
              ),
              ListTile(
                leading: Icon(Icons.assignment, color: Colors.blue),
                title: Text('生态地质垂直剖面测量记录表'),
                onTap: () => Navigator.pop(context, '2'),
              ),
              ListTile(
                leading: Icon(Icons.assignment, color: Colors.orange[200]),
                title: Text('生态地质垂直剖面测量点林草调查表(乔木)'),
                onTap: () => Navigator.pop(context, '3'),
              ),
              ListTile(
                leading: Icon(Icons.assignment, color: Colors.orange[300]),
                title: Text('生态地质垂直剖面测量点林草调查表(灌木)'),
                onTap: () => Navigator.pop(context, '4'),
              ),
              ListTile(
                leading: Icon(Icons.assignment, color: Colors.orange[400]),
                title: Text('生态地质垂直剖面测量点林草调查表(草木)'),
                onTap: () => Navigator.pop(context, '5'),
              ),
            ],
          ),
        );
      },
    );
    // 如果用户没选（点击空白处取消了），就结束
    if (selectedTemplate == null) return;
    // 假设未选择路线就不能打开，之前已经做了限制。这里提取选择的路线ID传给下个页面做“点号”关联
    String currentPathId = _selectedLine?.properties['线路号'] ?? "UNKNOWN";

    // 使用 Navigator.push 推出全屏表单，并等待表单页点击右上角“完成提交”后返回数据
    final resultData = await Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true, // 加上这个属性，动画会从下往上弹出，像一个系统的全屏工作表
        builder: (context) => FieldSurveyFormPage(
          currentGps: _currentLocation!, // 将真实的GPS（WGS84）发给表单页面自动填进去
          taskId: _currentTaskId!,       // 传真实的TaskId
          pathId: currentPathId,         // 传路线号
          templateType: selectedTemplate, // 将选中的模板类型传给表单页
        ),
      ),
    );

    // 如果用户填好了点完成回来了（不是点左上角的取消）
    if (resultData != null) {
      setState(() {
        // 生成一个包含坐标和海量表据数据的新集合，压入地图的已打卡列表中
        final newData = {
          'location': existingPoint?['location'] ?? _currentLocation,
          'form_data': resultData, // 这里保存了近50个字段的完整数据字典！
        };

        if (existingPoint == null) {
          _actualPoints.add(newData); // 新增打点
        } else {
          _actualPoints[pointIndex!] = newData; // 修改打点
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("该点位调查数据已提交！"), backgroundColor: Colors.green),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey, // 绑定 Key
      appBar: AppBar(
        title: Text(_currentTaskTitle, style: TextStyle(fontSize: 16)),
        backgroundColor: Colors.green,
        // 如果使用了 endDrawer，Flutter 会自动在右上角加上三点（汉堡）图标
        // 我们也可以自定义这个按钮
        actions: [
          IconButton(
            icon: Icon(Icons.more_vert), // 右上角的三个点
            onPressed: () {
              // 划出右侧侧边栏
              _scaffoldKey.currentState?.openEndDrawer();
            },
          ),
        ],
      ),

      // ================= 右侧滑出的侧边栏 =================
      endDrawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(color: Colors.green),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(Icons.account_circle, size: 60, color: Colors.white),
                  SizedBox(height: 10),
                  Text(
                    '野外调查员',
                    style: TextStyle(color: Colors.white, fontSize: 18),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: Icon(Icons.map),
              title: Text('主控地图'),
              onTap: () => Navigator.pop(context), // 点击后收起侧边栏
            ),
            ListTile(
              leading: Icon(Icons.assignment),
              title: Text('我的任务'),
              onTap: () async {
                // 1. 收起侧边栏
                Navigator.pop(context);
                // 2. 跳转到任务页面，并等待其返回结果
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => TaskScreen()),
                );
                // 3. 接收返回的路线数据，绘制在地图上
                if (result != null) {
                  _loadTaskToMap(result);
                }
              },
            ),
            Divider(),
            ListTile(
              leading: Icon(Icons.settings),
              title: Text('离线地图下载'), // 占位
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: Icon(Icons.logout, color: Colors.red),
              title: Text('退出登录', style: TextStyle(color: Colors.red)),
              onTap: () {
                // 1. 先收起侧边栏抽屉
                Navigator.pop(context);
                // 2. 弹出确认对话框
                _showLogoutDialog();
              },
            ),
          ],
        ),
      ),

      // ================= 核心：地图引擎部分 =================
      body: Stack(
        children: [
          // 1. 地图层
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              center: LatLng(30.2741, 120.1551), // 默认
              zoom: 15.0,
              // 点击地图空白处，计算距离并选中路线
              onTap: (tapPosition, LatLng clickedLatLngGcj) {
                // 注意：由于底层是高德，点击获取的坐标自带 GCJ-02 偏移！
                TaskLine? closestLine;
                double minDistance = double.infinity;

                for (var taskLine in _taskLines) {
                  for (var wgsPoint in taskLine.points) {
                    // 我们要把后台真实的 WGS84 路线点 转换成 GCJ02 再去比较距离
                    LatLng gcjPoint = _wgsToGcj(wgsPoint);
                    // LatLng gcjPoint = wgsPoint;
                    double distance = Distance().as(
                      LengthUnit.Meter,
                      clickedLatLngGcj,
                      gcjPoint,
                    );
                    if (distance < 500 && distance < minDistance) {
                      // 50米容差
                      minDistance = distance;
                      closestLine = taskLine;
                    }
                  }
                }

                setState(() {
                  _selectedLine = closestLine; // 若没点中，就是 null，卡片消失
                });
              },
            ),
            children: [
              // //天地图矢量底图 (需把你的tk替换掉末尾的 YOUR_TK)
              // TileLayer(
              //   urlTemplate:
              //       'http://t0.tianditu.gov.cn/vec_w/wmts?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0&LAYER=vec&STYLE=default&TILEMATRIXSET=w&FORMAT=tiles&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&tk=e48048d5cca7c1445e08536185177ba2',
              //   userAgentPackageName: 'com.LaputaMao.field_survey',
              // ),
              // //天地图矢量注记图层（文字地名，通常盖在底图上面一层）
              // TileLayer(
              //   urlTemplate:
              //       'http://t0.tianditu.gov.cn/cva_w/wmts?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0&LAYER=cva&STYLE=default&TILEMATRIXSET=w&FORMAT=tiles&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&tk=e48048d5cca7c1445e08536185177ba2',
              //   backgroundColor: Colors.transparent, // 背景透明，只盖文字
              //   userAgentPackageName: 'com.LaputaMao.field_survey',
              // ),
              TileLayer(
                // 1. 高德卫星纯影像底图图层
                urlTemplate:
                    'https://webst0{s}.is.autonavi.com/appmaptile?style=6&x={x}&y={y}&z={z}&key=2f0fcf7450f5ef55cf109244f76c3235',
                subdomains: const ['1', '2', '3', '4'],
                userAgentPackageName: 'com.LaputaMao.field_survey',
              ),

              TileLayer(
                // 2. 高德路网及地名标签图层 (透明背景盖在卫星图上)
                urlTemplate:
                    'https://wprd0{s}.is.autonavi.com/appmaptile?x={x}&y={y}&z={z}&lang=zh_cn&size=1&scl=1&style=8&key=2f0fcf7450f5ef55cf109244f76c3235',
                subdomains: const ['1', '2', '3', '4'],
                backgroundColor: Colors.transparent, // 必须透明
                userAgentPackageName: 'com.LaputaMao.field_survey',
              ),

              // --------------- 渲染 GeoJSON 的多段线 ---------------
              PolylineLayer(
                polylines: _taskLines.map((taskLine) {
                  bool isSelected = (_selectedLine == taskLine);
                  // 遍历路线，视图层实时 _wgsToGcj 转换
                  final gcjPoints = taskLine.points
                      .map((p) => _wgsToGcj(p))
                      // .map((p) => p)
                      .toList();

                  return Polyline(
                    points: gcjPoints,
                    strokeWidth: isSelected ? 6.0 : 4.0, // 选中加粗
                    color: isSelected
                        ? Colors.yellowAccent
                        : Colors.blueAccent.withOpacity(0.8), // 选中高亮黄
                  );
                }).toList(),
              ),

              // --------------- 渲染 GeoJSON 规划的点位 ---------------
              // MarkerLayer(
              //   markers: _taskPoints.map((taskPoint) {
              //     return Marker(
              //       point: taskPoint.location,
              //       width: 45,
              //       height: 45,
              //       child: GestureDetector(
              //         onTap: () {
              //           // 点击规划点，展示后端派发的 properties
              //           _showPropertiesSheet(taskPoint.properties, "规划调查点");
              //         },
              //         child: const Icon(
              //           Icons.place,
              //           color: Colors.purple,
              //           size: 40,
              //         ),
              //       ),
              //     );
              //   }).toList(),
              // ),
              PolylineLayer(
                polylines: _historyActualRoutes.map((historyRoutePoints) {
                  return Polyline(
                    points: historyRoutePoints
                        .map((p) => _wgsToGcj(p))
                        .toList(),
                    strokeWidth: 5.0,
                    color: Colors.green, // 实际被走完的轨迹用纯绿色
                  );
                }).toList(),
              ),

              // ============ ⚠️ 你本次启动点击“开始调查”后的新产生轨迹 ============
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _actualRoute.map((p) => _wgsToGcj(p)).toList(),
                    strokeWidth: 5.0,
                    // 本次运行产生的新轨迹为了做区分，可以用稍微亮一点/有冲刺感的颜色（比如橘色或者深绿色）
                    color: Colors.greenAccent,
                  ),
                ],
              ),
              // ---------------实际打卡的点位 (使用显眼的橙色/深绿)---------------
              // MarkerLayer(
              //   markers: _actualPoints.asMap().entries.map((entry) {
              //     int index = entry.key;
              //     Map<String, dynamic> pt = entry.value;
              //     return Marker(
              //       point: pt['location'],
              //       width: 45,
              //       height: 45,
              //       child: GestureDetector(
              //         onTap: () =>
              //             _openSurveyForm(existingPoint: pt, pointIndex: index),
              //         child: const Icon(
              //           Icons.where_to_vote,
              //           color: Colors.orange,
              //           size: 40,
              //         ),
              //       ),
              //     );
              //   }).toList(),
              // ),
              //
              // // 用户实时的当前GPS小蓝点指示
              // if (_currentLocation != null)
              //   MarkerLayer(
              //     markers: [
              //       Marker(
              //         point: _currentLocation!,
              //         width: 20,
              //         height: 20,
              //         child: Container(
              //           decoration: BoxDecoration(
              //             color: Colors.blueAccent,
              //             shape: BoxShape.circle,
              //             border: Border.all(color: Colors.white, width: 2),
              //           ),
              //         ),
              //       ),
              //     ],
              //   ),
              MarkerLayer(
                markers: [
                  // 1. 展现尚未调查的规划打点
                  ..._taskPoints.map(
                    (taskPoint) => Marker(
                      point: _wgsToGcj(taskPoint.location), // todo 转 GCJ
                      width: 45,
                      height: 45,
                      child: GestureDetector(
                        onTap: () {
                          _showPropertiesSheet(taskPoint.properties, "规划调查点");
                          // ScaffoldMessenger.of(context).showSnackBar(
                          //   SnackBar(content: Text("请选中关联的路线后开始调查")),
                          // );
                        },
                        child: Icon(
                          Icons.place,
                          color: Colors.purple,
                          size: 40,
                        ),
                      ),
                    ),
                  ),
                  // 2. 真实打卡点(你在填表存库时存的是WGS84, _actualPoints 内提取 location 转 GCJ)
                  ..._actualPoints.asMap().entries.map(
                    (entry) => Marker(
                      point: _wgsToGcj(entry.value['location']),
                      // todo转 GCJ
                      width: 45,
                      height: 45,
                      child: GestureDetector(
                        onTap: () => _openSurveyForm(
                          existingPoint: entry.value,
                          pointIndex: entry.key,
                        ),
                        child: Icon(
                          Icons.where_to_vote,
                          color: Colors.orange,
                          size: 40,
                        ),
                      ),
                    ),
                  ),
                  // 3. 当前实时 GPS 小蓝点
                  if (_currentLocation != null)
                    Marker(
                      point: _wgsToGcj(_currentLocation!), // todo 转 GCJ
                      width: 20,
                      height: 20,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blueAccent,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),

          // 右下角的悬浮按钮组
          // Positioned(
          //   bottom: 30,
          //   right: 20,
          //   child: Column(
          //     mainAxisSize: MainAxisSize.min,
          //     crossAxisAlignment: CrossAxisAlignment.end,
          //     children: [
          //       // 解锁的打点按钮（只有surveying为true才显示出橘色打点按钮）
          //       if (_isSurveying) ...[
          //         FloatingActionButton(
          //           heroTag: "mark_btn",
          //           backgroundColor: Colors.orange,
          //           onPressed: () => _openSurveyForm(),
          //           child: Icon(Icons.add_location_alt, size: 30),
          //         ),
          //         SizedBox(height: 20), // 按钮间距
          //       ],
          //
          //       // 核心控制按钮 (未开始: 绿色开始按键; 进行中: 红色长按结束健)
          //       _isSurveying
          //           ? HoldToCompleteButton(onCompleted: _endSurvey) // 调用自定义长按按钮
          //           : FloatingActionButton.extended(
          //               heroTag: "start_btn",
          //               backgroundColor: Colors.green,
          //               onPressed: _startSurvey,
          //               icon: Icon(Icons.play_arrow),
          //               label: Text(
          //                 "开始调查",
          //                 style: TextStyle(fontWeight: FontWeight.bold),
          //               ),
          //             ),
          //     ],
          //   ),
          // ),
          // 2. 顶部悬浮属性卡片（不遮挡和变暗地图）
          if (_selectedLine != null && !_isSurveying)
            Positioned(
              top: 50, // 距离顶部安全区往下一点
              left: 20,
              right: 20,
              child: Card(
                elevation: 8,
                shadowColor: Colors.black45,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Padding(
                  padding: EdgeInsets.all(15),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "已选定路线详情",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.green[800],
                            ),
                          ),
                          GestureDetector(
                            onTap: () => setState(() => _selectedLine = null),
                            // 右上角关闭按钮
                            child: Icon(Icons.close, color: Colors.grey),
                          ),
                        ],
                      ),
                      Divider(),
                      // 动态展示该线的 properties
                      ..._selectedLine!.properties.entries
                          .map(
                            (entry) => Padding(
                              padding: EdgeInsets.only(bottom: 6.0),
                              child: Text(
                                "${entry.key}: ${entry.value}",
                                style: TextStyle(fontSize: 14),
                              ),
                            ),
                          )
                          .toList(),
                    ],
                  ),
                ),
              ),
            ),

          // 3. 右下角的悬浮按钮组 (修改了“开始按钮”属性)
          Positioned(
            bottom: 30,
            right: 20,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (_isSurveying) ...[
                  FloatingActionButton(
                    heroTag: "mark_btn",
                    backgroundColor: Colors.orange,
                    onPressed: () => _openSurveyForm(),
                    child: Icon(Icons.add_location_alt, size: 30),
                  ),
                  SizedBox(height: 20),
                ],

                _isSurveying
                    ? HoldToCompleteButton(onCompleted: _endSurvey)
                    : FloatingActionButton.extended(
                        heroTag: "start_btn",
                        // 若未选择线，按钮置灰
                        backgroundColor: _selectedLine == null
                            ? Colors.grey
                            : Colors.green,
                        onPressed: () {
                          if (_selectedLine == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text("请先点击地图选择一条红色的规划路线")),
                            );
                            return; // 拒绝开始
                          }
                          _startSurvey(); // 开始调查
                        },
                        icon: Icon(Icons.play_arrow),
                        label: Text(
                          "开始调查",
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
