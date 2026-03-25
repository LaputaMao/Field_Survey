import 'dart:async';
import 'dart:io';
import 'package:field_survey/screens/task_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dotted_border/dotted_border.dart';
import '../widgets/hold_to_complete_button.dart'; // 引入咱们刚写的长按按钮

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final MapController _mapController = MapController();

  // 右上角打开侧边栏的 Key
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  String _currentTaskTitle = "请从右侧菜单选择任务";

  // 模拟当前选中的任务路线（将来由上一个页面或后端传入 GeoJSON 解析出来）
  List<LatLng> _plannedRoute = [];
  List<Marker> _surveyMarkers = []; // 调查点

  // 状态控制
  bool _isSurveying = false; // 是否在调查中
  LatLng? _currentLocation; // 手机实时GPS位置
  StreamSubscription<Position>? _positionStream; // 轨迹监听流

  // 路线与点位存储
  List<LatLng> _actualRoute = []; // 实际走过的绿色轨迹
  List<Map<String, dynamic>> _actualPoints = []; // 实际打的点

  @override
  void initState() {
    super.initState();
    // 页面初始化时，尝试获取一次当前位置并自动跳转
    _initCurrentLocation();
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

  // ============== 核心逻辑：开始调查与结束调查 ==============
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
            _mapController.move(_currentLocation!, 16.0); // 视角跟随移动
          });
        });
  }

  void _endSurvey() {
    // 停止定位监听，打包数据发送后端，清空地图
    _positionStream?.cancel();

    // TODO: 调用后端接口打发数据
    // api.uploadSurveyResult(route: _actualRoute, points: _actualPoints);

    setState(() {
      _isSurveying = false;
      _actualRoute.clear();
      _actualPoints.clear();
      _currentLocation = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('调查已结束，数据已打包上传云端！'),
        backgroundColor: Colors.green,
      ),
    );
  }

  // ============== 核心逻辑：打点填表 (底部弹窗) ==============
  void _openSurveyForm({Map<String, dynamic>? existingPoint, int? pointIndex}) {
    if (_currentLocation == null && existingPoint == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("GPS信号弱，请稍后再试")));
      return;
    }

    // 表单控制器与照片列表
    TextEditingController descController = TextEditingController(
      text: existingPoint?['desc'] ?? '',
    );
    List<String> photos = existingPoint != null
        ? List<String>.from(existingPoint['photos'])
        : [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // 允许弹窗被键盘顶起
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        // 使用 StatefulBuilder 为了在弹窗内刷新照片列表
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            // 拍照方法
            Future<void> _takePhoto() async {
              final ImagePicker _picker = ImagePicker();
              final XFile? image = await _picker.pickImage(
                source: ImageSource.camera,
              );
              if (image != null) {
                setModalState(() {
                  photos.add(image.path); // 将本地图片路径加入列表
                });
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom, // 防止键盘遮挡
                left: 20,
                right: 20,
                top: 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      existingPoint == null ? "新增调查点" : "查看/编辑调查点",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 10),
                    // 仅显示GPS坐标（防作弊）
                    Text(
                      "打卡坐标：${existingPoint?['location']?.latitude ?? _currentLocation!.latitude}, ${existingPoint?['location']?.longitude ?? _currentLocation!.longitude}",
                      style: TextStyle(color: Colors.grey),
                    ),
                    SizedBox(height: 15),
                    TextField(
                      controller: descController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: '环境描述与现场情况',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    SizedBox(height: 15),

                    // 照片区域
                    Text("现场照片", style: TextStyle(fontWeight: FontWeight.bold)),
                    SizedBox(height: 10),
                    Container(
                      height: 80,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          // 1. 虚线拍照大按钮
                          GestureDetector(
                            onTap: _takePhoto,
                            child: DottedBorder(
                              color: Colors.grey,
                              strokeWidth: 2,
                              dashPattern: [6, 4], // 虚线长度
                              child: Container(
                                width: 80,
                                height: 80,
                                child: Center(
                                  child: Icon(
                                    Icons.add,
                                    size: 40,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: 10),

                          // 2. 已拍好的照片快视图列阵
                          ...photos.asMap().entries.map((entry) {
                            int idx = entry.key;
                            String path = entry.value;
                            return Stack(
                              children: [
                                Container(
                                  margin: EdgeInsets.only(right: 10),
                                  width: 80,
                                  height: 80, // 和虚线框等大
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: Colors.grey.shade300,
                                    ),
                                    image: DecorationImage(
                                      image: FileImage(File(path)),
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                                // 右上角的删除小红点
                                Positioned(
                                  top: 0,
                                  right: 10,
                                  child: GestureDetector(
                                    onTap: () {
                                      setModalState(() => photos.removeAt(idx));
                                    },
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.red,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        Icons.close,
                                        size: 18,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ],
                      ),
                    ),
                    SizedBox(height: 20),

                    // 底部按钮栏
                    Row(
                      children: [
                        if (existingPoint != null) // 如果是查看模式，允许删除整个点位
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red,
                              ),
                              onPressed: () {
                                setState(
                                  () => _actualPoints.removeAt(pointIndex!),
                                );
                                Navigator.pop(context);
                              },
                              child: Text('删除打卡点'),
                            ),
                          ),
                        if (existingPoint != null) SizedBox(width: 10),

                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                            ),
                            onPressed: () {
                              // 保存逻辑
                              final newData = {
                                'location':
                                    existingPoint?['location'] ??
                                    _currentLocation,
                                'desc': descController.text,
                                'photos': photos,
                              };
                              setState(() {
                                if (existingPoint == null) {
                                  _actualPoints.add(newData); // 新增
                                } else {
                                  _actualPoints[pointIndex!] = newData; // 修改
                                }
                              });
                              Navigator.pop(context); // 收起弹窗
                            },
                            child: Text(
                              existingPoint == null ? '保存点位' : '更新保存',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 20),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
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
                  // _loadTaskToMap(result);
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
                // TODO: 清除 Token 并退回登录页
              },
            ),
          ],
        ),
      ),

      // ================= 核心：地图引擎部分 =================
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              center: LatLng(30.2741, 120.1551),
              zoom: 15.0,
              maxZoom: 18.0,
            ),
            children: [
              // 天地图矢量底图 (需把你的tk替换掉末尾的 YOUR_TK)
              // TileLayer(
              //   urlTemplate:
              //       'http://t0.tianditu.gov.cn/vec_w/wmts?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0&LAYER=vec&STYLE=default&TILEMATRIXSET=w&FORMAT=tiles&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&tk=e48048d5cca7c1445e08536185177ba2',
              //   userAgentPackageName: 'com.LaputaMao.field_survey',
              // ),
              // 1. 高德卫星纯影像底图图层
              TileLayer(
                urlTemplate:
                    'https://webst0{s}.is.autonavi.com/appmaptile?style=6&x={x}&y={y}&z={z}',
                subdomains: const ['1', '2', '3', '4'],
                userAgentPackageName: 'com.LaputaMao.field_survey',
              ),
              // 2. 高德路网及地名标签图层 (透明背景盖在卫星图上)
              TileLayer(
                urlTemplate:
                    'https://wprd0{s}.is.autonavi.com/appmaptile?x={x}&y={y}&z={z}&lang=zh_cn&size=1&scl=1&style=8',
                subdomains: const ['1', '2', '3', '4'],
                backgroundColor: Colors.transparent, // 必须透明
                userAgentPackageName: 'com.LaputaMao.field_survey',
              ),

              // 天地图矢量注记图层（文字地名，通常盖在底图上面一层）
              // TileLayer(
              //   urlTemplate:
              //       'http://t0.tianditu.gov.cn/cva_w/wmts?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0&LAYER=cva&STYLE=default&TILEMATRIXSET=w&FORMAT=tiles&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&tk=e48048d5cca7c1445e08536185177ba2',
              //   backgroundColor: Colors.transparent, // 背景透明，只盖文字
              //   userAgentPackageName: 'com.LaputaMao.field_survey',
              // ),
              // 实际行走的绿色轨迹
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _actualRoute,
                    strokeWidth: 5.0,
                    color: Colors.green,
                  ),
                ],
              ),

              // 实际打卡的点位 (使用显眼的橙色/深绿)
              MarkerLayer(
                markers: _actualPoints.asMap().entries.map((entry) {
                  int index = entry.key;
                  Map<String, dynamic> pt = entry.value;
                  return Marker(
                    point: pt['location'],
                    width: 45,
                    height: 45,
                    child: GestureDetector(
                      onTap: () =>
                          _openSurveyForm(existingPoint: pt, pointIndex: index),
                      child: const Icon(
                        Icons.where_to_vote,
                        color: Colors.orange,
                        size: 40,
                      ),
                    ),
                  );
                }).toList(),
              ),

              // 用户实时的当前GPS小蓝点指示
              if (_currentLocation != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _currentLocation!,
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
          Positioned(
            bottom: 30,
            right: 20,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // 解锁的打点按钮（只有surveying为true才显示出橘色打点按钮）
                if (_isSurveying) ...[
                  FloatingActionButton(
                    heroTag: "mark_btn",
                    backgroundColor: Colors.orange,
                    onPressed: () => _openSurveyForm(),
                    child: Icon(Icons.add_location_alt, size: 30),
                  ),
                  SizedBox(height: 20), // 按钮间距
                ],

                // 核心控制按钮 (未开始: 绿色开始按键; 进行中: 红色长按结束健)
                _isSurveying
                    ? HoldToCompleteButton(onCompleted: _endSurvey) // 调用自定义长按按钮
                    : FloatingActionButton.extended(
                        heroTag: "start_btn",
                        backgroundColor: Colors.green,
                        onPressed: _startSurvey,
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
