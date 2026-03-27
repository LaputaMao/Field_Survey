import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dotted_border/dotted_border.dart';
import 'package:latlong2/latlong.dart';

class FieldSurveyFormPage extends StatefulWidget {
  final LatLng currentGps; // 传入GPS位置
  final String routeId; // 传入选中的路线号
  final String templateType; // 新增：接收模板类型

  const FieldSurveyFormPage({
    Key? key,
    required this.currentGps,
    required this.routeId,
    required this.templateType,
  }) : super(key: key);

  @override
  _FieldSurveyFormPageState createState() => _FieldSurveyFormPageState();
}

// 定义照片列表和表单数据的统一存储
class _FieldSurveyFormPageState extends State<FieldSurveyFormPage> {
  // 一个大 Map，用于在内存里装载所有用户填写的、自动生成的数据
  final Map<String, dynamic> _formData = {};

  // 模块3的内部标签页控制器
  int _module3CurrentTab = 0;

  @override
  void initState() {
    super.initState();
    _initAutoFields();
  }

  // ============== 核心逻辑：集中初始化所有“自动”字段 ==============
  void _initAutoFields() {
    String today =
        "${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}";

    // todo 自动填写数据
    _formData.addAll({
      // 模块0
      '剖面特征描述': '无', // 自动样例
      // 模块1
      '图幅名': '北京市',
      '图幅号': 'J50E001010',
      '所属三级生态基础分区': '海河北系平原城镇和农田生态区',
      '日期': today,
      '路线号': '${widget.routeId}',
      '剖面号':'2.2.1-${widget.routeId}-P001',
      '经度/纬度':
          'E:${widget.currentGps.longitude.toStringAsFixed(4)} / N:${widget.currentGps.latitude.toStringAsFixed(4)}',
      '地面高程': '58 m',
      '平面坐标': 'X:3432123, Y:4123412',
      '地理位置': '北京市海淀区',
      // 模块2
      '地貌类型': '低海拔平原',
      '坡度': '1°',
      '所属流域': '海河区-潮白、北运、蓟运河水系-北四河下游平原',
      '土地利用类型': '人工牧草地',
      '生态系统类型': '人工（栽培）草地',
      '多年平均降水量': '540.9 mm',
      // 模块3A/B
      '植被类型': '栽培植被',
      '土壤类型': '铁铝土-湿热铁铝土-砖红壤',
      '侵蚀类型': '水力侵蚀',
      '侵蚀强度': '微度',
      // 模块4
      '柱状剖面描述': '无',
      '景观描述内容': '无',
      // 模块5
      '调查人': '李四',
      '记录人': '李四',
      '审核人': '',

      // 照片数据列表初始化
      '照片_柱状剖面图': <Map<String, String>>[],
      '照片_空间位置截图': <Map<String, String>>[],
      '照片_样品照片': <Map<String, String>>[],
      '照片_景观描述照片': <Map<String, String>>[],
      'dynamic_assets_ecoProblem': <Map<String, dynamic>>[],
      'dynamic_assets_sample_0': <Map<String, dynamic>>[], // A.植被的样品
      'dynamic_assets_sample_1': <Map<String, dynamic>>[], // B.土壤的样品
      'dynamic_assets_sample_2': <Map<String, dynamic>>[], // C.成土母质的样品
      'dynamic_assets_sample_3': <Map<String, dynamic>>[], // D.包气带的样品
      'dynamic_assets_sample_4': <Map<String, dynamic>>[], // E.风化壳的样品
      'dynamic_assets_sample_5': <Map<String, dynamic>>[], // F.成土母岩的样品
      'dynamic_assets_sample_6': <Map<String, dynamic>>[], // F.水的样品
    });
  }

  // ============== 通用 UI 构建器方法 ==============

  // 注意这里的 targetMap 参数！这就是巧妙之处：如果不传，就默认改 _formData；
  // 如果传了动态结构体字典，就改那个结构体的数据！
  Map<String, dynamic> get _defaultMap => _formData;

  // 1. 构建类型 自动 字段的显示框
  Widget _buildAutoBox(String label, {Map<String, dynamic>? targetMap}) {
    final map = targetMap ?? _defaultMap;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: TextFormField(
        key: ValueKey("${map.hashCode}_auto_$label"),
        // ⭐ 新增：这把钥匙用字典的内存地址+标签名组成，绝对唯一！
        initialValue: map[label] ?? '获取中...',
        readOnly: false,
        // 只读
        style: TextStyle(color: Colors.grey[1000], fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
            color: Colors.green[800],
            fontWeight: FontWeight.bold,
          ),
          filled: true,
          fillColor: Colors.grey[200],
          isDense: true,
          border: OutlineInputBorder(
            borderSide: BorderSide.none,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }

  // 2. 构建用户填写框
  Widget _buildInput(String label, {Map<String, dynamic>? targetMap}) {
    final map = targetMap ?? _defaultMap;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: TextFormField(
        key: ValueKey("${map.hashCode}_input_$label"),
        // ⭐ 新增：这把钥匙用字典的内存地址+标签名组成，绝对唯一！
        onChanged: (val) => map[label] = val,
        minLines: 1,
        // 关键1：最小1行
        maxLines: null,
        // 关键2：最大行数无限制，文本越多框越长
        keyboardType: TextInputType.multiline,
        // 关键3：允许多行输入
        style: TextStyle(color: Colors.grey[1000], fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
            color: Colors.green[800],
            fontWeight: FontWeight.bold,
          ),
          filled: true,
          fillColor: Colors.grey[200],
          isDense: true,
          border: OutlineInputBorder(
            borderSide: BorderSide.none,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }

  // 3. 构建下拉选择框
  Widget _buildDropdown(
    String label,
    List<String> items, {
    Map<String, dynamic>? targetMap,
  }) {
    final map = targetMap ?? _defaultMap;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: DropdownButtonFormField<String>(
        key: ValueKey("${map.hashCode}_drop_$label"),
        // ⭐ 修改位置 1：增加 isExpanded 属性
        // 作用：强制下拉框内容填充可用空间，而不是由内容撑开宽度
        isExpanded: true,

        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
            color: Colors.green[800],
            fontWeight: FontWeight.bold,
            // 此处的 overflow 对标签起作用
            overflow: TextOverflow.ellipsis,
          ),
          filled: true,
          fillColor: Colors.grey[200],
          isDense: true,
          border: OutlineInputBorder(
            borderSide: BorderSide.none,
            borderRadius: BorderRadius.circular(8),
          ),
        ),

        // ⭐ 修改位置 2：对 DropdownMenuItem 的 child 进行包裹
        items: items.map((e) => DropdownMenuItem(
          value: e,
          child: Text(
            e,
            // 作用：防止下拉列表中的长文本再次触发溢出
            overflow: TextOverflow.ellipsis,
            softWrap: false,
          ),
        )).toList(),

        onChanged: (val) {
          setState(() => map[label] = val);
        },

        // ⭐ 修改位置 3：增加 selectedItemBuilder (可选但推荐)
        // 作用：控制“已选中”状态在输入框里的显示样式，确保它也不会溢出
        selectedItemBuilder: (BuildContext context) {
          return items.map<Widget>((String item) {
            return Text(
              item,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14),
            );
          }).toList();
        },
      ),
    );
  }

  // 4. 构建拍照横向列表框（支持多图）
  Widget _buildPhotoField(
    String title,
    String mapKey, {
    Map<String, dynamic>? targetMap,
  }) {
    final map = targetMap ?? _defaultMap;
    // 为了容错，如果这个键尚未初始化，先初始化它
    if (map[mapKey] == null) {
      map[mapKey] = <Map<String, String>>[];
    }
    List<Map<String, String>> photos = map[mapKey] as List<Map<String, String>>;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Text(
            title,
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
        ),
        Container(
          height: 100,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              // 拍照按钮
              GestureDetector(
                onTap: () async {
                  final picker = ImagePicker();
                  final XFile? img = await picker.pickImage(
                    source: ImageSource.camera,
                  );
                  if (img != null) {
                    // 生成基于当前时间的时间戳ID，如20260320_194859
                    DateTime now = DateTime.now();
                    String timeStampStr =
                        "${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}";
                    String photoId = "IMG_$timeStampStr";

                    setState(() {
                      photos.add({'id': photoId, 'path': img.path});
                    });
                  }
                },
                child: DottedBorder(
                  color: Colors.grey,
                  strokeWidth: 2,
                  dashPattern: [6, 4],
                  child: Container(
                    width: 80,
                    height: 80,
                    child: Icon(Icons.camera_alt, color: Colors.grey),
                  ),
                ),
              ),
              SizedBox(width: 10),
              // 照片陈列
              ...photos.asMap().entries.map((e) {
                final photoData = e.value;
                return Stack(
                  children: [
                    // 点击缩略图放大查看
                    GestureDetector(
                      onTap: () {
                        // 推送一个全屏的图片查看器
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => Scaffold(
                              appBar: AppBar(
                                title: Text(photoData['id']!),
                                backgroundColor: Colors.white,
                              ),
                              backgroundColor: Colors.white,
                              body: Center(
                                child: InteractiveViewer(
                                  // 支持双指缩放、拖拽
                                  child: Image.file(File(photoData['path']!)),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                      child: Container(
                        margin: EdgeInsets.only(right: 10),
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white),
                          image: DecorationImage(
                            image: FileImage(File(photoData['path']!)),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                    // 底部覆盖层展示生成的编号
                    Positioned(
                      bottom: 4,
                      left: 0,
                      child: Container(
                        width: 80,
                        color: Colors.black54,
                        padding: EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          photoData['id']!.substring(4), // 显示时间戳部分
                          style: TextStyle(color: Colors.white, fontSize: 9),
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    // 删除按钮小红叉，放在右上角
                    Positioned(
                      right: 0,
                      top: -10,
                      child: IconButton(
                        icon: Container(
                          decoration: BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.close,
                            size: 20,
                            color: Colors.white,
                          ),
                        ),
                        onPressed: () => setState(() => photos.removeAt(e.key)),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ],
          ),
        ),
        SizedBox(height: 10),
      ],
    );
  }

  // 5. 态追加自定义结构体组
  Widget _buildDynamicCustomGroup_ecoProblem() {
    List<Map<String, dynamic>> dynamicAssets =
        _formData['dynamic_assets_ecoProblem'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 渲染已添加的各个自定义模块
        ...dynamicAssets.asMap().entries.map((entry) {
          int index = entry.key;
          Map<String, dynamic> itemMap = entry.value;

          return Card(
            color: Colors.orange[50], // 给定一个醒目的外框背景
            margin: EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "生态问题 #${index + 1}",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange[900],
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.delete, color: Colors.red),
                        onPressed: () =>
                            setState(() => dynamicAssets.removeAt(index)),
                      ),
                    ],
                  ),
                  // todo 在这里，我们就组装你需要的结构体了！将 itemMap 传入 targetMap
                  Row(
                    children: [
                      Expanded(
                        child: _buildDropdown('生态问题类型', [
                          '水土流失型',
                          '沙化型',
                          '石漠化型',
                          '冻融型',
                          '盐渍化型',
                          '生境破碎化',
                          '区域地下水位下降显著',
                          '森林退化',
                          '草地退化',
                          '湿地退化',
                          '冰川退缩',
                          '多年冻土消融',
                          '水土保持',
                          '水源涵养',
                          '防风固沙',
                          '固碳',
                        ], targetMap: itemMap),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: _buildDropdown('生态问题程度', [
                          '微度',
                          '轻度',
                          '中度',
                          '强度',
                          '极强度',
                          '剧烈',
                          '重度',
                          '极重度',
                        ], targetMap: itemMap),
                      ),
                    ],
                  ),
                  _buildDropdown('生态问题影响因素', [
                    '人为',
                    '天然',
                    '人为和天然',
                  ], targetMap: itemMap),
                  _buildInput('修复措施', targetMap: itemMap),
                ],
              ),
            ),
          );
        }).toList(),

        // “新建某某某” 按钮（做得和Input输入框一样长）
        InkWell(
          onTap: () {
            setState(() {
              // 每当点击，就往动态列表里塞一个空字典和特有的照片List。
              // 上面的 .map 就会渲染出多一个卡片！
              dynamicAssets.add(<String, dynamic>{
                '时间记录': DateTime.now().toString().substring(0, 16),
                '照片_记录': <Map<String, String>>[],
              });
            });
          },
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              border: Border.all(
                color: Colors.grey[400]!,
                style: BorderStyle.solid,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add, color: Colors.green[800]),
                SizedBox(width: 8),
                Text(
                  "新建生态问题",
                  style: TextStyle(
                    color: Colors.green[800],
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDynamicCustomGroup_sample(String listKey) {
    // 增加一个防御性初始化（如果没找到，就给它一个空数组防报错）
    if (_formData[listKey] == null) {
      _formData[listKey] = <Map<String, dynamic>>[];
    }

    // 这里不再写死，而是根据传入的 listKey 去拿数据
    List<Map<String, dynamic>> dynamicAssets = _formData[listKey];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 渲染已添加的各个自定义模块
        ...dynamicAssets.asMap().entries.map((entry) {
          int index = entry.key;
          Map<String, dynamic> itemMap = entry.value;

          return Card(
            color: Colors.blue[50], // 给定一个醒目的外框背景
            margin: EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "样品 #${index + 1}",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange[900],
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.delete, color: Colors.red),
                        onPressed: () =>
                            setState(() => dynamicAssets.removeAt(index)),
                      ),
                    ],
                  ),
                  // todo 在这里，我们就组装你需要的结构体了！将 itemMap 传入 targetMap
                  Row(
                    children: [
                      // Expanded(
                      //   child: _buildDropdown('样品类型', ['表层土样', '深层土样', '岩石样']),
                      // ),
                      // SizedBox(width: 8),
                      Expanded(
                        child: _buildInput('采样深度(cm)', targetMap: itemMap),
                      ),
                    ],
                  ),
                  _buildInput('样品编号', targetMap: itemMap),
                  _buildPhotoField('样品照片', '照片_记录', targetMap: itemMap),
                ],
              ),
            ),
          );
        }).toList(),

        // “新建某某某” 按钮（做得和Input输入框一样长）
        InkWell(
          onTap: () {
            setState(() {
              // 每当点击，就往动态列表里塞一个空字典和特有的照片List。
              // 上面的 .map 就会渲染出多一个卡片！
              dynamicAssets.add(<String, dynamic>{
                '时间记录': DateTime.now().toString().substring(0, 16),
                '照片_记录': <Map<String, String>>[],
              });
            });
          },
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              border: Border.all(
                color: Colors.grey[400]!,
                style: BorderStyle.solid,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add, color: Colors.green[800]),
                SizedBox(width: 8),
                Text(
                  "新建样品",
                  style: TextStyle(
                    color: Colors.green[800],
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ============== 页面构建 ==============
  @override
  Widget build(BuildContext context) {
    // 通过 widget.templateType 判断使用什么标题，后续你可以使用 if-else 渲染整块不同的树
    String title = "测量记录表";
    if (widget.templateType == '1') title = "生态地质调查点记录表";
    if (widget.templateType == '2') title = "生态地质垂直剖面测量记录表";
    if (widget.templateType == '3') title = "生态地质垂直剖面测量点林草调查表";
    return Scaffold(
      appBar: AppBar(
        title: Text('生态地质垂直剖面测量记录表'),
        titleTextStyle: TextStyle(color: Colors.black, fontSize: 18),
        backgroundColor: Colors.green,
        actions: [
          TextButton(
            onPressed: () {
              // TODO: 进行表单校验后退出并返回 formData 给调用者
              Navigator.pop(context, _formData);
            },
            child: Text(
              "完成提交",
              style: TextStyle(color: Colors.white, fontSize: 15),
            ),
          ),
        ],
      ),
      // 外层使用 ListView 避免键盘遮挡报错
      body: ListView(
        padding: EdgeInsets.all(12),
        children: [
          // ================= 模块 0: 总览图 =================
          ExpansionTile(
            initiallyExpanded: true,
            title: Text('拍照模块', style: TextStyle(fontWeight: FontWeight.bold)),
            children: [
              _buildPhotoField('柱状剖面图', '照片_柱状剖面图'),
              // _buildAutoBox('剖面特征描述'),
              _buildPhotoField('景观描述照片', '照片_景观描述照片'),
              // _buildPhotoField('空间位置截图', '照片_空间位置截图'),
            ],
          ),

          // ================= 模块 1: 基础信息 =================
          ExpansionTile(
            initiallyExpanded: true,
            title: Text(
              '基础信息模块',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            children: [
              // 空行防止字段被遮挡
              Row(),
              _buildInput('工作区'),
              // _buildAutoBox('图幅名/图幅号'),
              Row(
                children: [
                  Expanded(child: _buildAutoBox('图幅名')),
                  SizedBox(width: 8),
                  Expanded(child: _buildAutoBox('图幅号')),
                ],
              ),
              _buildAutoBox('所属三级生态基础分区'),
              // _buildDropdown('剖面类型', ['自然剖面', '人工剖面', '浅钻']),
              // _buildDropdown('天气', ['晴朗', '多云', '阴天', '小雨', '大雨', '雪']),
              Row(
                children: [
                  Expanded(
                    child: _buildDropdown('剖面类型', ['自然剖面', '人工剖面', '浅钻']),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: _buildDropdown('天气', [
                      '晴朗',
                      '多云',
                      '阴天',
                      '小雨',
                      '大雨',
                      '雪',
                    ]),
                  ),
                ],
              ),
              _buildAutoBox('日期'),
              // _buildAutoBox('路线号/点号/剖面号'),
              Row(
                children: [
                  Expanded(child: _buildAutoBox('路线号')),
                  SizedBox(width: 8),
                  Expanded(child: _buildAutoBox('剖面号')),
                ],
              ),
              _buildAutoBox('经度/纬度'),
              _buildAutoBox('平面坐标'),
              Row(
                children: [
                  Expanded(flex: 2, child: _buildAutoBox('地理位置')),
                  SizedBox(width: 8),
                  Expanded(child: _buildAutoBox('地面高程')),
                ],
              ),
            ],
          ),

          // ================= 模块 2: 地貌与生态特征 =================
          ExpansionTile(
            initiallyExpanded: true,
            title: Text(
              '地类信息模块',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            children: [
              Row(),
              Row(
                children: [
                  Expanded(child: _buildAutoBox('地貌类型')),
                  SizedBox(width: 8),
                  Expanded(
                    child: _buildDropdown('地貌部位', [
                      '坡顶(顶部)',
                      '坡上(上部)',
                      '坡中(中部)',
                      '坡下(下部)',
                      '坡麓(底部)',
                      '高阶地(洪－冲积平原)',
                      '低阶地(河流冲积平原)',
                      '河漫滩',
                      '底部(排水线)',
                      '潮上带',
                      '潮间带',
                      '其他',
                    ]),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(child: _buildAutoBox('坡度')),
                  SizedBox(width: 8),
                  Expanded(child: _buildAutoBox('所属流域')),
                ],
              ),
              // _buildAutoBox('土地利用/生态系统类型'),
              Row(
                children: [
                  Expanded(child: _buildAutoBox('土地利用类型')),
                  SizedBox(width: 8),
                  Expanded(child: _buildAutoBox('生态系统类型')),
                ],
              ),
              Row(
                children: [
                  Expanded(child: _buildInput('地表蒸散量')),
                  SizedBox(width: 8),
                  Expanded(child: _buildInput('地下水埋深')),
                  SizedBox(width: 8),
                  Expanded(child: _buildAutoBox('多年平均降水量')),
                ],
              ),
              // _buildDropdown('生态问题类型/程度等级', [
              //   '水土流失 - 轻度',
              //   '水土流失 - 重度',
              //   '沙化 - 轻度',
              //   '石漠化',
              // ]),
              // _buildDropdown('影响因素', ['气候变化', '人类活动', '地质灾害', '综合因素']),
              // _buildInput('修复措施'),
              _buildDynamicCustomGroup_ecoProblem(),
            ],
          ),

          // ================= 模块 3: 详细特征观测 =================
          ExpansionTile(
            initiallyExpanded: true, // 核心模块默认展开
            title: Text(
              '特征模块',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            children: [
              // 使用横向分段控件选择 A/B/C
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(
                      value: 0,
                      label: Text('植被', style: TextStyle(fontSize: 15)),
                    ),
                    ButtonSegment(
                      value: 1,
                      label: Text('土壤', style: TextStyle(fontSize: 15)),
                    ),
                    ButtonSegment(
                      value: 2,
                      label: Text('成土母质', style: TextStyle(fontSize: 15)),
                    ),
                    ButtonSegment(
                      value: 3,
                      label: Text('包气带', style: TextStyle(fontSize: 15)),
                    ),
                    ButtonSegment(
                      value: 4,
                      label: Text('风化壳', style: TextStyle(fontSize: 15)),
                    ),
                    ButtonSegment(
                      value: 5,
                      label: Text('成土母岩', style: TextStyle(fontSize: 15)),
                    ),
                    ButtonSegment(
                      value: 6,
                      label: Text('水', style: TextStyle(fontSize: 15)),
                    ),
                  ],
                  selected: {_module3CurrentTab},
                  onSelectionChanged: (Set<int> newSelection) {
                    setState(() => _module3CurrentTab = newSelection.first);
                  },
                ),
              ),
              SizedBox(height: 10),

              // 标签面板 A: 植被特征
              if (_module3CurrentTab == 0) ...[
                Row(
                  children: [
                    Expanded(flex: 3, child: _buildAutoBox('植被类型')),
                    SizedBox(width: 8),
                    Expanded(flex: 3, child: _buildInput('植被覆盖度(%)')),
                    SizedBox(width: 8),
                    Expanded(flex: 2, child: _buildInput('高度(m)')),
                  ],
                ),
                _buildDropdown('起源', ['自然植被', '人工植被']),
                Row(
                  children: [
                    Expanded(child: _buildInput('植被优势种')),
                    SizedBox(width: 8),
                    Expanded(child: _buildInput('乡土适生种')),
                    SizedBox(width: 8),
                    Expanded(child: _buildInput('引进适生种')),
                  ],
                ),
                _buildDynamicCustomGroup_sample("dynamic_assets_sample_0"),
              ],

              // 标签面板 B: 土壤特征
              if (_module3CurrentTab == 1) ...[
                // _buildAutoBox('土壤类型/侵蚀/强度'),
                Row(
                  children: [
                    Expanded(child: _buildAutoBox('土壤类型')),
                    SizedBox(width: 8),
                    Expanded(child: _buildAutoBox('侵蚀类型')),
                    SizedBox(width: 8),
                    Expanded(child: _buildAutoBox('侵蚀强度')),
                  ],
                ),
                Row(
                  children: [
                    Expanded(child: _buildInput('土壤颜色')),
                    SizedBox(width: 8),
                    Expanded(child: _buildInput('厚度(cm)')),
                    SizedBox(width: 8),
                    Expanded(child: _buildInput('土被覆盖率')),
                  ],
                ),
                _buildInput('分层结构'),
                _buildInput('土壤质地'),
                Row(
                  children: [
                    Expanded(child: _buildInput('紧实度')),
                    SizedBox(width: 8),
                    Expanded(child: _buildInput('结持性')),
                    SizedBox(width: 8),
                    Expanded(child: _buildInput('砾石含量(%)')),
                  ],
                ),
                Row(
                  children: [
                    Expanded(child: _buildInput('pH值')),
                    SizedBox(width: 8),
                    Expanded(child: _buildInput('温度(℃)')),
                    SizedBox(width: 8),
                    Expanded(child: _buildInput('含水量')),
                  ],
                ),
                Row(
                  children: [
                    Expanded(child: _buildInput('电导率')),
                    SizedBox(width: 8),
                    Expanded(child: _buildInput('含盐量')),
                  ],
                ),
                _buildDynamicCustomGroup_sample("dynamic_assets_sample_1"),
              ],

              // 标签面板 C: 母质特征
              if (_module3CurrentTab == 2) ...[
                Row(
                  children: [
                    Expanded(
                      child: _buildDropdown('母质类型', [
                        '风积沙',
                        '原生黄土',
                        '黄土状物质 (次生黄土)',
                        '残积物',
                        '坡积物',
                        '冲积物',
                        '海岸沉积物',
                        '湖泊沉积物',
                        '河流沉积物',
                        '火成碎屑沉积物',
                        '冰川沉积物 (冰碛物)',
                        '冰水沉积物',
                        '有机沉积物',
                        '崩积物',
                        '(古) 红黏土',
                        '其他',
                      ]),
                    ),
                    SizedBox(width: 8),
                    Expanded(child: _buildInput('颜色')),
                    SizedBox(width: 8),
                    Expanded(child: _buildInput('厚度(m)')),
                  ],
                ),
                Row(
                  children: [
                    Expanded(child: _buildInput('成土母质层结构')),
                    SizedBox(width: 8),
                    Expanded(child: _buildInput('成土母质松散度')),
                  ],
                ),
                _buildInput('成土母质成分及比例'),
                Divider(),
                // Text('包气带与风化壳', style: TextStyle(color: Colors.grey)),
                _buildDynamicCustomGroup_sample("dynamic_assets_sample_2"),
              ],

              if (_module3CurrentTab == 3) ...[
                Row(
                  children: [
                    Expanded(child: _buildInput('包气带厚度(m)')),
                    SizedBox(width: 8),
                    Expanded(child: _buildInput('包气带渗透系数')),
                  ],
                ),
                _buildInput('包气带垂直结构'),
                _buildDynamicCustomGroup_sample("dynamic_assets_sample_3"),
              ],

              if (_module3CurrentTab == 4) ...[
                Row(
                  children: [
                    Expanded(child: _buildInput('风化壳类型')),
                    SizedBox(width: 8),
                    Expanded(child: _buildInput('风化壳厚度')),
                  ],
                ),
                Row(
                  children: [
                    Expanded(child: _buildInput('风化壳风化程度')),
                    SizedBox(width: 8),
                    Expanded(child: _buildInput('风化壳垂直结构')),
                  ],
                ),
                _buildDynamicCustomGroup_sample("dynamic_assets_sample_4"),
              ],

              if (_module3CurrentTab == 5) ...[
                Row(
                  children: [
                    Expanded(child: _buildInput('成土母岩岩性')),
                    SizedBox(width: 8),
                    Expanded(child: _buildInput('成土母岩颜色')),
                  ],
                ),
                _buildDynamicCustomGroup_sample("dynamic_assets_sample_5"),
              ],

              if (_module3CurrentTab == 6) ...[
                _buildDynamicCustomGroup_sample("dynamic_assets_sample_6"),
              ],

              // Text('水', style: TextStyle(
              //   fontSize: 20,
              //   color: Colors.green[800],
              //   fontWeight: FontWeight.bold,
              // )),
              // Text('', style: TextStyle()),
            ],
          ),

          // ================= 模块 4: 采样与影像资料 =================
          ExpansionTile(
            initiallyExpanded: true,
            title: Text('概述模块', style: TextStyle(fontWeight: FontWeight.bold)),
            children: [
              Text('', style: TextStyle()),
              _buildAutoBox('柱状剖面描述'),
              _buildAutoBox('景观描述内容'),
            ],
          ),

          // ================= 模块 5: 责任声明 =================
          ExpansionTile(
            initiallyExpanded: true,
            title: Text(
              '填表人员记录',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            children: [
              Text('', style: TextStyle(color: Colors.grey)),
              Row(
                children: [
                  Expanded(child: _buildAutoBox('调查人')),
                  SizedBox(width: 8),
                  Expanded(child: _buildAutoBox('记录人')),
                  SizedBox(width: 8),
                  Expanded(child: _buildAutoBox('审核人')),
                ],
              ),
            ],
          ),
          SizedBox(height: 50), // 底部留白
        ],
      ),
    );
  }
}
