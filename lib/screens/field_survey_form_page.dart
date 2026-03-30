import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dotted_border/dotted_border.dart';
import 'package:latlong2/latlong.dart';
import 'package:dio/dio.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:field_survey/config/api_config.dart';
import 'package:proj4dart/proj4dart.dart';
import 'dart:math' as math;

class FieldSurveyFormPage extends StatefulWidget {
  final LatLng currentGps; // 传入GPS位置
  final int taskId; // ⭐ 新增：整型的 taskId
  final String pathId; // ⭐ 修改：原本的 routeId 改叫 pathId 更贴切（类似 xL_001）
  final String templateType; // 新增：接收模板类型
  final String? autoScreenshotPath; // ⭐ 新增：可选的系统截图路径

  const FieldSurveyFormPage({
    Key? key,
    required this.currentGps,
    required this.taskId, // 必传
    required this.pathId, // 必传
    required this.templateType,
    this.autoScreenshotPath, // ⭐ 加入构造器
  }) : super(key: key);

  @override
  _FieldSurveyFormPageState createState() => _FieldSurveyFormPageState();
}

// 定义照片列表和表单数据的统一存储
class _FieldSurveyFormPageState extends State<FieldSurveyFormPage> {
  // 一个大 Map，用于在内存里装载所有用户填写的、自动生成的数据
  final Map<String, dynamic> _formData = {};

  // tip 二级下拉数据结构
  final Map<String, List<String>> _categoryData = {
    "植被": ["乔木", "灌木", "草本", "荒漠植被"],
    "土壤": ["红壤", "黄壤", "棕壤", "粘土"],
    "成土母质": ["残积物", "坡积物", "洪积物", "冲积物"],
  };

  // 模块3的内部标签页控制器
  int _module3CurrentTab = 0;

  // 注意：修改为你真实的后端 IP 或域名
  final String _baseUrl = ApiConfig.baseUrl;

  // ============== 新增：自动填表懒加载逻辑 ==============
  Future<void> _fetchAutoFillData() async {
    // tip 1. 甲方可能会增减的自动计算字段，统一在这里维护：
    List<String> autoFieldsReq = [
      "所属三级生态基础分区",
      "土纲土亚纲土类",
      // "图幅名",
      // "图幅号",
      // "所属生态区",
      // "年降雨量", // 在这里任意添加后台支持的字段
    ];

    // 先把要拉取的字段全部初始化为 "计算中..."
    setState(() {
      for (var field in autoFieldsReq) {
        _formData[field] = "计算中...";
      }
    });

    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString('jwt_token');

      var dio = Dio();
      var response = await dio.post(
        "$_baseUrl/user/auto-fill",
        data: {
          "task_id": widget.taskId, // ⭐ 传入真实的 taskId
          "path_id": widget.pathId, // 点位接口也需要关联某条线，可以传这个
          "point_type": widget.templateType,
          "longitude": widget.currentGps.longitude,
          "latitude": widget.currentGps.latitude,
          "fields": autoFieldsReq, // 传给后台
        },
        options: Options(headers: {"Authorization": "Bearer $token"}),
      );

      if (response.statusCode == 200 && response.data['data'] != null) {
        Map<String, dynamic> resData = response.data['data'];

        setState(() {
          resData.forEach((key, value) {
            // 2. tip 如果后台返回的是嵌套字典，比如 "土纲土亚纲土类": {"土亚纲": "...", "土类":"..."}
            if (value is Map) {
              value.forEach((subKey, subValue) {
                _formData[subKey] = _formatNumber(subValue);
              });
            } else {
              // 3. 常平级字段直接赋值
              _formData[key] = _formatNumber(value);
            }
          });
        });
      }
    } catch (e) {
      debugPrint("自动填表获取失败: $e");
      // 可以选择静默失败或弹窗
      setState(() {
        // 获取失败的替换为空白，方便用户手填
        for (var field in autoFieldsReq) {
          if (_formData[field] == "计算中...") _formData[field] = "";
        }
      });
    }
  }

  // 小工具：确保如果是数值，自动保留2位小数
  String _formatNumber(dynamic value) {
    if (value is num) {
      return value.toDouble().toStringAsFixed(2);
    }
    return value?.toString() ?? "";
  }

  // ============== 新增：混合打点上传逻辑 ==============
  Future<void> _submitForm() async {
    // 弹出加载圈
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          Center(child: CircularProgressIndicator(color: Colors.green)),
    );

    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString('jwt_token');

      // 1. 分离文本和照片数据
      Map<String, dynamic> textData = {};
      List<MapEntry<String, MultipartFile>> fileEntries = [];

      for (var key in _formData.keys) {
        var value = _formData[key];

        if (value is List) {
          // A. 处理公共层级的普通照片栏
          if (key.startsWith('照片_') ||
              key.contains('相片') ||
              key.contains('照片')) {
            for (var photo in value) {
              if (photo is Map && photo.containsKey('path')) {
                fileEntries.add(
                  MapEntry(
                    key, // 外层键名直接传
                    await MultipartFile.fromFile(
                      photo['path']!,
                      filename: "${photo['id']}.jpg",
                    ),
                  ),
                );
              }
            }
          }
          // B. 处理结构体内部的数据 (重点修复区域)
          else if (key.startsWith('dynamic_assets_')) {
            List<Map<String, dynamic>> cleanStructList = [];

            for (int i = 0; i < value.length; i++) {
              var struct = value[i];
              Map<String, dynamic> cleanStruct = {};

              if (struct is Map) {
                // ⭐ 修复关键：使用 for...in...entries 代替 forEach，确保 await 真正阻塞等待！
                for (var entry in struct.entries) {
                  var sKey = entry.key;
                  var sValue = entry.value;

                  // 识别结构体里带有“照片”字样的 List 层
                  if (sValue is List &&
                      (sKey.startsWith('照片_') || sKey.contains('照片'))) {
                    // 这是子结构体里的照片，我们需要给它取一个混合键名防止前后端混淆
                    // 格式：父级名_索引_子集名，例如："dynamic_assets_sample_0_0_照片_记录"
                    String complexKey = "${key}_${i}_$sKey";

                    for (var photo in sValue) {
                      if (photo is Map && photo.containsKey('path')) {
                        fileEntries.add(
                          MapEntry(
                            complexKey,
                            await MultipartFile.fromFile(
                              photo['path']!,
                              filename: "${photo['id']}.jpg",
                            ),
                          ),
                        );
                      }
                    }
                  } else {
                    // 普通文本塞回结构体
                    cleanStruct[sKey] = sValue;
                  }
                }
                cleanStructList.add(cleanStruct);
              }
            }
            textData[key] = cleanStructList; // 剔除了照片后干净的 JSON 阵列
          }
        } else {
          // 常规外层纯文本录入
          textData[key] = value;
        }
      }

      // 2. 将数据组装为后端需要的 FormData 形态
      var dio = Dio();
      FormData formData = FormData.fromMap({
        // 后端要求的三个基础参数
        "task_id": widget.taskId, // ⭐ 传入真实的 taskId
        // "path_id": widget.pathId, // (可选) 如果你上传点位接口也需要关联某条线，可以传这个
        "lon": widget.currentGps.longitude,
        "lat": widget.currentGps.latitude,
        // 所有纯文本统一转化为一个大 JSON 字符串
        "properties": jsonEncode(textData),
      });

      // 补充剥离出来的照片池
      formData.files.addAll(fileEntries);

      // 3. 一次性发射给后端
      var response = await dio.post(
        "$_baseUrl/user/points/upload",
        data: formData,
        options: Options(headers: {"Authorization": "Bearer $token"}),
      );

      Navigator.pop(context); // 关闭加载圈

      if (response.statusCode == 200 || response.statusCode == 201) {
        // 上传成功，带着数据返回上一页并提示
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('调查点位提交成功！'), backgroundColor: Colors.green),
        );
        Navigator.pop(context, _formData);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('提交失败，服务端返回：${response.statusCode}')),
        );
      }
    } on DioException catch (dioError) {
      // ⭐ 核心抓错逻辑：提取后端真正返回的 message
      Navigator.pop(context); // 关加载圈
      String errorMsg = "请求失败";

      if (dioError.response != null) {
        // 如果后端有返回具体 JSON 原因（比如 {"message": "task_id 不能为空"}）
        final errorData = dioError.response?.data;
        errorMsg =
            "HTTP ${dioError.response?.statusCode}: ${errorData.toString()}";
      } else {
        errorMsg = dioError.message ?? "网络连接异常";
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('提交被拒绝:\n$errorMsg'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 5), // 显示久一点方便你看
        ),
      );
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('未知错误: $e')));
    }
  }

  @override
  void initState() {
    super.initState();
    _initAutoFields();
    //开启异步懒加载后台经纬度相交计算数据
    _fetchAutoFillData();
  }

  // ============== 核心逻辑：集中初始化所有“自动”字段 ==============
  void _initAutoFields() {
    String today =
        "${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}";
    double currentLon = widget.currentGps.longitude;
    double currentLat = widget.currentGps.latitude;

    // 1. 定义源坐标系 (WGS84 GPS原始坐标)
    var projWGS84 = Projection.get('EPSG:4326')!;

    // 2. 注册并定义目标坐标系：CGCS2000 3度带 (举例：中央经线120度，EPSG代码为4528)
    // 小鱼注意：不同省份的中央经线不同！如果是全国通用的项目，可能需要根据当前经度动态计算 EPSG 编号。
    // 这里填入的字符串是标准的 proj4 通用定义，可以在 epsg.io 上查到。
    String cgcs2000Proj4Def =
        "+proj=tmerc +lat_0=0 +lon_0=120 +k=1 +x_0=39500000 +y_0=0 +ellps=GRS80 +units=m +no_defs";
    var projCGCS2000 = Projection.add('EPSG:4528', cgcs2000Proj4Def);

    // 3. 执行转换
    var pointWGS = Point(x: currentLon, y: currentLat);
    var pointPlanar = projWGS84.transform(projCGCS2000, pointWGS);

    // 4. 拼装字符串
    String planarString =
        'X: ${pointPlanar.x.toStringAsFixed(3)} m,  Y: ${pointPlanar.y.toStringAsFixed(3)} m';

    // 1. 三套模板都要用到的【公共基础字段】
    _formData.addAll({
      '表格模板编号': '${widget.templateType}',
      // // 模块0
      // '剖面特征描述': '无',
      // // 模块1
      // '图幅名': '北京市',
      // '图幅号': 'J50E001010',
      // '所属三级生态基础分区': '海河北系平原城镇和农田生态区',
      '日期': today,
      '路线号': '${widget.pathId}',
      '经度/纬度':
          'E:${widget.currentGps.longitude.toStringAsFixed(8)} / N:${widget.currentGps.latitude.toStringAsFixed(8)}',
      // '地面高程': '58 m',
      '平面坐标': planarString,
      // '地理位置': '北京市海淀区',
      // // 模块2
      // '地貌类型': '低海拔平原',
      // '坡度': '1°',
      // '所属流域': '海河区-潮白、北运、蓟运河水系-北四河下游平原',
      // '土地利用类型': '人工牧草地',
      // '生态系统类型': '人工（栽培）草地',
      // '多年平均降水量': '540.9 mm',
      // // 模块3A/B
      // '植被类型': '栽培植被',
      // '土壤类型': '铁铝土-湿热铁铝土-砖红壤',
      // '侵蚀类型': '水力侵蚀',
      // '侵蚀强度': '微度',
      // 模块4Projection.get('EPSG:4549')!
      '柱状剖面描述':
          '植被：描述植被类型、林草覆盖度、优势植物种，植被根系发育深度等；\n土壤：描述土体构型特征、土壤层颜色、厚度、质地、结构、砾石含量、含水率、pH值、根系深度、根系分布特征，表层土壤侵蚀程度，与下覆成土母质接触关系；\n成土母质：描述成土母质类型、厚度、结构、垂向变化、根系分布特征及与下覆基岩的接触关系等；\n成土母岩：描述岩性、主要岩石颜色、结构、构造、主要矿物、层理/节理产状、抗风化能力等；\n包气带：描述厚度、结构、含水性、渗透系数及分布特征等；\n风化壳：描述类型、厚度、风化程度、物质组成、垂直结构、分布特征等；\n总结描述成土岩石-成土母质-土壤-植被间关系、影响等。',
      '景观描述内容':
          '剖面点所处区域生态景观及突出的生态特征、生态问题的照片。描述内容：\n1、区域自然条件：描述该地理位置、气候区等整体特征；\n2、植被：植被类型、垂直结构及覆盖度等；\n3、生态系统及土地利用类型：描述生态系统类型、分布，土地利用类型、分布等；\n4、生态问题：生态问题类型、程度、分布、人类活动扰动、保护修复措施。',
      // 模块5
      '调查人': '李四',
      '记录人': '李四',
      '审核人': '',

      // 照片数据列表初始化
      '照片_柱状剖面图': <Map<String, String>>[],
      '照片_空间位置截图': widget.autoScreenshotPath != null
          ? <Map<String, String>>[
              {
                'id': "IMG_${DateTime.now().millisecondsSinceEpoch}",
                'path': widget.autoScreenshotPath!,
              },
            ]
          : <Map<String, String>>[], // 未传入则留空,
      '照片_样品照片': <Map<String, String>>[],
      '照片_景观描述照片': <Map<String, String>>[],
      '林草样方照片': <Map<String, String>>[],
      'dynamic_assets_ecoProblem': <Map<String, dynamic>>[],
      'dynamic_assets_sample_0': <Map<String, dynamic>>[], // A.植被的样品
      'dynamic_assets_sample_1': <Map<String, dynamic>>[], // B.土壤的样品
      'dynamic_assets_sample_2': <Map<String, dynamic>>[], // C.成土母质的样品
      'dynamic_assets_sample_3': <Map<String, dynamic>>[], // D.包气带的样品
      'dynamic_assets_sample_4': <Map<String, dynamic>>[], // E.风化壳的样品
      'dynamic_assets_sample_5': <Map<String, dynamic>>[], // F.成土母岩的样品
      'dynamic_assets_sample_6': <Map<String, dynamic>>[], // F.水的样品
    });
    // 2. 根据不同模板，初始化其【专属独有字段】和【动态表单列表】
    if (widget.templateType == '1') {
      // ---- 调查点记录表 专属初始化 ----
      _formData.addAll({
        // 初始化调查点独有的照片或组
        '点号': '生态区编号-${widget.pathId}-D',
      });
    } else if (widget.templateType == '2') {
      // ---- 生态地质垂直剖面测量记录表 专属初始化 (保留你原来写好的) ----
      _formData.addAll({
        // 初始化调查点独有的照片或组
        '剖面号': '生态区编号-${widget.pathId}-P',
      });
    } else if (widget.templateType == '3') {
      // ---- 林草调查表 专属初始化 ----
      _formData.addAll({'样地号': '生态区编号-${widget.pathId}-YD'});
    } else if (widget.templateType == '4') {
      // ---- 林草调查表 专属初始化 ----
      _formData.addAll({'样方号': '生态区编号-${widget.pathId}-YF'});
    } else if (widget.templateType == '5') {
      // ---- 林草调查表 专属初始化 ----
      _formData.addAll({'样方号': '生态区编号-${widget.pathId}-YF'});
    }
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
        key: ValueKey("${map.hashCode}_auto_${label}_${map[label]}"),
        // ⭐ 新增：这把钥匙用字典的内存地址+标签名组成，绝对唯一！
        minLines: 1,
        // 关键1：最小1行
        maxLines: null,
        // 关键2：最大行数无限制，文本越多框越长
        keyboardType: TextInputType.multiline,
        // 关键3：允许多行输入
        initialValue: map[label] ?? '计算中...',
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
    String currentVal = (map[label] ?? '').toString();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: TextFormField(
        key: ValueKey("${map.hashCode}_input_$label"),
        // 这把钥匙用字典的内存地址+标签名组成，绝对唯一！
        // tip 必须加上这行！下次销毁重建时，它会从大字典里读取刚才写的值！
        initialValue: currentVal,
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
    // ⭐ 新增：安全读取当前值，如果当前值不在 items 列表里，强制设为 null
    String? currentVal = map[label] != null ? map[label].toString() : null;
    if (currentVal != null && !items.contains(currentVal)) {
      currentVal = null;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: DropdownButtonFormField<String>(
        key: ValueKey("${map.hashCode}_drop_$label"),
        // ⭐ 修改位置 1：增加 isExpanded 属性
        // 作用：强制下拉框内容填充可用空间，而不是由内容撑开宽度
        // ⭐ 极其重要：绑定当前值，重建时才不会变成白板
        initialValue: currentVal,
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
          // 禁用时变灰
          isDense: true,
          border: OutlineInputBorder(
            borderSide: BorderSide.none,
            borderRadius: BorderRadius.circular(8),
          ),
        ),

        // ⭐ 修改位置 2：对 DropdownMenuItem 的 child 进行包裹
        items: items
            .map(
              (e) => DropdownMenuItem(
                value: e,
                child: Text(
                  e,
                  // 作用：防止下拉列表中的长文本再次触发溢出
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                ),
              ),
            )
            .toList(),

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

  // ⭐ 修改位置：新增二级联动组件函数
  Widget _buildLinkedDropdown(
    String label,
    Map<String, List<String>> dataMap, {
    Map<String, dynamic>? targetMap,
  }) {
    final map = targetMap ?? _defaultMap;
    // 存储格式建议为 "大类-具体值"，或者只存具体值
    String? currentVal = map[label]?.toString();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: InkWell(
        // 使用 InkWell 模拟下拉框点击外观
        onTap: () => _showLevelOnePicker(label, dataMap, map),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            labelStyle: TextStyle(
              color: Colors.green[800],
              fontWeight: FontWeight.bold,
              overflow: TextOverflow.ellipsis,
            ),
            filled: true,
            fillColor: Colors.grey[200],
            isDense: true,
            suffixIcon: Icon(Icons.arrow_drop_down),
            // 模拟下拉箭头
            border: OutlineInputBorder(
              borderSide: BorderSide.none,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Text(
            currentVal ?? "请选择",
            style: TextStyle(
              fontSize: 14,
              color: currentVal == null ? Colors.grey : Colors.black,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }

  // ⭐ 逻辑实现：第一级选择（大类）
  void _showLevelOnePicker(
    String label,
    Map<String, List<String>> dataMap,
    Map map,
  ) {
    showModalBottomSheet(
      context: context,
      builder: (context) => ListView(
        shrinkWrap: true,
        children: dataMap.keys
            .map(
              (category) => ListTile(
                title: Text(category),
                onTap: () {
                  Navigator.pop(context);
                  // 选中大类后，立即进入第二级选择
                  _showLevelTwoPicker(label, category, dataMap[category]!, map);
                },
              ),
            )
            .toList(),
      ),
    );
  }

  // ⭐ 逻辑实现：第二级选择（具体值）
  void _showLevelTwoPicker(
    String label,
    String category,
    List<String> subItems,
    Map map,
  ) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppBar(
            title: Text("选择$category的具体类型", style: TextStyle(fontSize: 16)),
            automaticallyImplyLeading: false,
            elevation: 0,
            backgroundColor: Colors.transparent,
          ),
          Expanded(
            child: ListView(
              shrinkWrap: true,
              children: subItems
                  .map(
                    (item) => ListTile(
                      title: Text(item),
                      onTap: () {
                        setState(() {
                          // 存储最终结果，例如 "植被: 乔木"
                          map[label] = "$category: $item";
                        });
                        Navigator.pop(context);
                      },
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
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

  // ================= 模板渲染引擎 =================

  // ▶ 模板1：生态地质调查点记录表
  List<Widget> _buildTemplate1() {
    return [
      // ================= 模块 0: 总览图 =================
      ExpansionTile(
        initiallyExpanded: true,
        maintainState: true, // ⭐ 新增：保持状态，收起不销毁内存
        title: Text('拍照模块', style: TextStyle(fontWeight: FontWeight.bold)),
        children: [
          _buildPhotoField('景观描述照片', '照片_景观描述照片'),
          _buildPhotoField('空间位置截图', '照片_空间位置截图'),
        ],
      ),

      // ================= 模块 1: 基础信息 =================
      ExpansionTile(
        initiallyExpanded: true,
        maintainState: true, // ⭐ 新增：保持状态，收起不销毁内存
        title: Text('基础信息模块', style: TextStyle(fontWeight: FontWeight.bold)),
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
          Row(
            children: [
              Expanded(child: _buildAutoBox('日期')),
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
          // _buildAutoBox('路线号/点号/剖面号'),
          Row(
            children: [
              Expanded(child: _buildAutoBox('路线号')),
              SizedBox(width: 8),
              Expanded(flex: 2, child: _buildAutoBox('剖面号')),
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
        maintainState: true, // ⭐ 新增：保持状态，收起不销毁内存
        title: Text('地类信息模块', style: TextStyle(fontWeight: FontWeight.bold)),
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
              Expanded(child: _buildAutoBox('坡向')),
            ],
          ),
          _buildAutoBox('所属流域'),
          Row(
            children: [
              Expanded(child: _buildLinkedDropdown('土地利用类型', _categoryData)),
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
      // ExpansionTile(
      //   initiallyExpanded: true, // 核心模块默认展开
      //   maintainState: true, // ⭐ 新增：保持状态，收起不销毁内存
      //   title: Text('特征模块', style: TextStyle(fontWeight: FontWeight.bold)),
      //   children: [
      //     // 使用横向分段控件选择 A/B/C
      //     Wrap(
      //       spacing: 8.0, // 左右间距
      //       runSpacing: 4.0, // 上下间距（换行后）
      //       children: List<Widget>.generate(7, (int index) {
      //         final labels = ['植被', '土壤', '成土母质', '包气带', '风化壳', '成土母岩', '水'];
      //         return ChoiceChip(
      //           label: Text(labels[index]),
      //           selected: _module3CurrentTab == index,
      //           onSelected: (bool selected) {
      //             setState(() {
      //               _module3CurrentTab = selected ? index : _module3CurrentTab;
      //             });
      //           },
      //         );
      //       }).toList(),
      //     ),
      //     SizedBox(height: 10),
      //
      //     // ⭐ 修改：用 IndexedStack 包裹所有的面板层！
      //     IndexedStack(
      //       index: _module3CurrentTab, // 当前显示第几个
      //       children: [
      //         // 标签面板 A: 植被特征
      //         if (_module3CurrentTab == 0) ...[
      //           Row(
      //             children: [
      //               Expanded(flex: 3, child: _buildAutoBox('植被类型')),
      //               SizedBox(width: 8),
      //               Expanded(flex: 3, child: _buildInput('植被覆盖度(%)')),
      //               SizedBox(width: 8),
      //               Expanded(flex: 2, child: _buildInput('高度(m)')),
      //             ],
      //           ),
      //           _buildDropdown('起源', ['自然植被', '人工植被']),
      //           Row(
      //             children: [
      //               Expanded(child: _buildInput('植被优势种')),
      //               SizedBox(width: 8),
      //               Expanded(child: _buildInput('乡土适生种')),
      //               SizedBox(width: 8),
      //               Expanded(child: _buildInput('引进适生种')),
      //             ],
      //           ),
      //           _buildDynamicCustomGroup_sample("dynamic_assets_sample_0"),
      //         ],
      //
      //         // 标签面板 B: 土壤特征
      //         if (_module3CurrentTab == 1) ...[
      //           // _buildAutoBox('土壤类型/侵蚀/强度'),
      //           Row(
      //             children: [
      //               Expanded(child: _buildAutoBox('土壤类型')),
      //               SizedBox(width: 8),
      //               Expanded(child: _buildAutoBox('侵蚀类型')),
      //               SizedBox(width: 8),
      //               Expanded(child: _buildAutoBox('侵蚀强度')),
      //             ],
      //           ),
      //           Row(
      //             children: [
      //               Expanded(child: _buildInput('土壤颜色')),
      //               SizedBox(width: 8),
      //               Expanded(child: _buildInput('厚度(cm)')),
      //               SizedBox(width: 8),
      //               Expanded(child: _buildInput('土被覆盖率')),
      //             ],
      //           ),
      //           _buildInput('分层结构'),
      //           _buildInput('土壤质地'),
      //           // Row(
      //           //   children: [
      //           //     Expanded(child: _buildInput('紧实度')),
      //           //     SizedBox(width: 8),
      //           //     Expanded(child: _buildInput('结持性')),
      //           //     SizedBox(width: 8),
      //           //     Expanded(child: _buildInput('砾石含量(%)')),
      //           //   ],
      //           // ),
      //           // Row(
      //           //   children: [
      //           //     Expanded(child: _buildInput('pH值')),
      //           //     SizedBox(width: 8),
      //           //     Expanded(child: _buildInput('温度(℃)')),
      //           //     SizedBox(width: 8),
      //           //     Expanded(child: _buildInput('含水量')),
      //           //   ],
      //           // ),
      //           // Row(
      //           //   children: [
      //           //     Expanded(child: _buildInput('电导率')),
      //           //     SizedBox(width: 8),
      //           //     Expanded(child: _buildInput('含盐量')),
      //           //   ],
      //           // ),
      //           _buildDynamicCustomGroup_sample("dynamic_assets_sample_1"),
      //         ],
      //
      //         // 标签面板 C: 母质特征
      //         if (_module3CurrentTab == 2) ...[
      //           Row(
      //             children: [
      //               Expanded(
      //                 child: _buildDropdown('母质类型', [
      //                   '风积沙',
      //                   '原生黄土',
      //                   '黄土状物质 (次生黄土)',
      //                   '残积物',
      //                   '坡积物',
      //                   '冲积物',
      //                   '海岸沉积物',
      //                   '湖泊沉积物',
      //                   '河流沉积物',
      //                   '火成碎屑沉积物',
      //                   '冰川沉积物 (冰碛物)',
      //                   '冰水沉积物',
      //                   '有机沉积物',
      //                   '崩积物',
      //                   '(古) 红黏土',
      //                   '其他',
      //                 ]),
      //               ),
      //               SizedBox(width: 8),
      //               Expanded(child: _buildInput('颜色')),
      //               SizedBox(width: 8),
      //               Expanded(child: _buildInput('厚度(m)')),
      //             ],
      //           ),
      //           Row(
      //             children: [
      //               Expanded(child: _buildInput('成土母质层结构')),
      //               SizedBox(width: 8),
      //               Expanded(child: _buildInput('成土母质松散度')),
      //             ],
      //           ),
      //           _buildInput('成土母质成分及比例'),
      //           Divider(),
      //           // Text('包气带与风化壳', style: TextStyle(color: Colors.grey)),
      //           _buildDynamicCustomGroup_sample("dynamic_assets_sample_2"),
      //         ],
      //
      //         if (_module3CurrentTab == 3) ...[
      //           Row(
      //             children: [
      //               Expanded(child: _buildInput('包气带厚度(m)')),
      //               SizedBox(width: 8),
      //               Expanded(child: _buildInput('包气带渗透系数')),
      //             ],
      //           ),
      //           _buildInput('包气带垂直结构'),
      //           _buildDynamicCustomGroup_sample("dynamic_assets_sample_3"),
      //         ],
      //
      //         if (_module3CurrentTab == 4) ...[
      //           Row(
      //             children: [
      //               Expanded(child: _buildInput('风化壳类型')),
      //               SizedBox(width: 8),
      //               Expanded(child: _buildInput('风化壳厚度')),
      //             ],
      //           ),
      //           Row(
      //             children: [
      //               Expanded(child: _buildInput('风化壳风化程度')),
      //               SizedBox(width: 8),
      //               Expanded(child: _buildInput('风化壳垂直结构')),
      //             ],
      //           ),
      //           _buildDynamicCustomGroup_sample("dynamic_assets_sample_4"),
      //         ],
      //
      //         if (_module3CurrentTab == 5) ...[
      //           Row(
      //             children: [
      //               Expanded(child: _buildInput('成土母岩岩性')),
      //               SizedBox(width: 8),
      //               Expanded(child: _buildInput('成土母岩颜色')),
      //             ],
      //           ),
      //           _buildDynamicCustomGroup_sample("dynamic_assets_sample_5"),
      //         ],
      //
      //         if (_module3CurrentTab == 6) ...[
      //           _buildDynamicCustomGroup_sample("dynamic_assets_sample_6"),
      //         ],
      //       ],
      //     ),
      //     // Text('水', style: TextStyle(
      //     //   fontSize: 20,
      //     //   color: Colors.green[800],
      //     //   fontWeight: FontWeight.bold,
      //     // )),
      //     // Text('', style: TextStyle()),
      //   ],
      // ),

      // ================= 模块 4: 采样与影像资料 =================
      // ================= 模块 3: 详细特征观测 =================
      ExpansionTile(
        initiallyExpanded: true,
        maintainState: true, // ⭐ 保证收起折叠面板时内部数据死死保留不销毁！
        title: Text('特征模块', style: TextStyle(fontWeight: FontWeight.bold)),
        children: [
          // 横向分段控件选择 (共 7 个标签)
          Wrap(
            spacing: 8.0,
            runSpacing: 4.0,
            children: List<Widget>.generate(7, (int index) {
              final labels = ['植被', '土壤', '成土母质', '包气带', '风化壳', '成土母岩', '水'];
              return ChoiceChip(
                label: Text(labels[index]),
                selected: _module3CurrentTab == index,
                onSelected: (bool selected) {
                  setState(
                    () => _module3CurrentTab = selected
                        ? index
                        : _module3CurrentTab,
                  );
                },
              );
            }).toList(),
          ),
          SizedBox(height: 10),

          // ⭐ 核心修复区域：IndexedStack 的 children 数组必须雷打不动地包含 7 个 Column
          IndexedStack(
            index: _module3CurrentTab, // 绑定当前应该显示第几个
            children: [
              // ----------------- [下标 0] 标签面板 A: 植被特征 -----------------
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
              ),

              // ----------------- [下标 1] 标签面板 B: 土壤特征 -----------------
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                  _buildDropdown('土壤质地', ['粘土', '壤土', '砂壤土', '壤砂土', '砂土']),
                  Row(
                    children: [
                      Expanded(child: _buildInput('紧实度')),
                      SizedBox(width: 8),
                      Expanded(
                        child: _buildDropdown('结持性', [
                          '疏松',
                          '坚实',
                          '很坚实',
                          '极坚实',
                        ]),
                      ),
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
              ),

              // ----------------- [下标 2] 标签面板 C: 母质特征 -----------------
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _buildDropdown('母质类型', ['风积沙', '原生黄土']),
                      ), // 选项可自行补全
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
                  _buildDynamicCustomGroup_sample("dynamic_assets_sample_2"),
                ],
              ),

              // ----------------- [下标 3] 标签面板 D: 包气带 -----------------
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
              ),

              // ----------------- [下标 4] 标签面板 E: 风化壳 -----------------
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
              ),

              // ----------------- [下标 5] 标签面板 F: 成土母岩 -----------------
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: _buildInput('成土母岩岩性')),
                      SizedBox(width: 8),
                      Expanded(child: _buildInput('成土母岩颜色')),
                    ],
                  ),
                  _buildDynamicCustomGroup_sample("dynamic_assets_sample_5"),
                ],
              ),

              // ----------------- [下标 6] 标签面板 G: 水 -----------------
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDynamicCustomGroup_sample("dynamic_assets_sample_6"),
                ],
              ),
            ],
          ),
        ],
      ),

      ExpansionTile(
        initiallyExpanded: true,
        maintainState: true, // ⭐ 新增：保持状态，收起不销毁内存
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
        maintainState: true, // ⭐ 新增：保持状态，收起不销毁内存
        title: Text('填表人员记录', style: TextStyle(fontWeight: FontWeight.bold)),
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
      SizedBox(height: 50),
      // 底部留白
    ];
  }

  // ▶ 模板2：生态地质垂直剖面测量记录表 (把你写好的代码平移过来)
  List<Widget> _buildTemplate2() {
    return [
      // ================= 模块 0: 总览图 =================
      ExpansionTile(
        initiallyExpanded: true,
        maintainState: true, // ⭐ 新增：保持状态，收起不销毁内存
        title: Text('拍照模块', style: TextStyle(fontWeight: FontWeight.bold)),
        children: [
          _buildPhotoField('柱状剖面图', '照片_柱状剖面图'),
          // _buildAutoBox('剖面特征描述'),
          _buildPhotoField('景观描述照片', '照片_景观描述照片'),
          _buildPhotoField('空间位置截图', '照片_空间位置截图'),
        ],
      ),

      // ================= 模块 1: 基础信息 =================
      ExpansionTile(
        initiallyExpanded: true,
        maintainState: true, // ⭐ 新增：保持状态，收起不销毁内存
        title: Text('基础信息模块', style: TextStyle(fontWeight: FontWeight.bold)),
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
              Expanded(child: _buildDropdown('剖面类型', ['自然剖面', '人工剖面', '浅钻'])),
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
        maintainState: true, // ⭐ 新增：保持状态，收起不销毁内存
        title: Text('地类信息模块', style: TextStyle(fontWeight: FontWeight.bold)),
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
      // ================= 模块 3: 详细特征观测 =================
      ExpansionTile(
        initiallyExpanded: true,
        maintainState: true, // ⭐ 保证收起折叠面板时内部数据死死保留不销毁！
        title: Text('特征模块', style: TextStyle(fontWeight: FontWeight.bold)),
        children: [
          // 横向分段控件选择 (共 7 个标签)
          Wrap(
            spacing: 8.0,
            runSpacing: 4.0,
            children: List<Widget>.generate(7, (int index) {
              final labels = ['植被', '土壤', '成土母质', '包气带', '风化壳', '成土母岩', '水'];
              return ChoiceChip(
                label: Text(labels[index]),
                selected: _module3CurrentTab == index,
                onSelected: (bool selected) {
                  setState(
                    () => _module3CurrentTab = selected
                        ? index
                        : _module3CurrentTab,
                  );
                },
              );
            }).toList(),
          ),
          SizedBox(height: 10),

          // ⭐ 核心修复区域：IndexedStack 的 children 数组必须雷打不动地包含 7 个 Column
          IndexedStack(
            index: _module3CurrentTab, // 绑定当前应该显示第几个
            children: [
              // ----------------- [下标 0] 标签面板 A: 植被特征 -----------------
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
              ),

              // ----------------- [下标 1] 标签面板 B: 土壤特征 -----------------
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                  _buildDropdown('土壤质地', ['粘土', '壤土', '砂壤土', '壤砂土', '砂土']),
                  Row(
                    children: [
                      Expanded(child: _buildInput('紧实度')),
                      SizedBox(width: 8),
                      Expanded(
                        child: _buildDropdown('结持性', [
                          '疏松',
                          '坚实',
                          '很坚实',
                          '极坚实',
                        ]),
                      ),
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
              ),

              // ----------------- [下标 2] 标签面板 C: 母质特征 -----------------
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _buildDropdown('母质类型', ['风积沙', '原生黄土']),
                      ), // 选项可自行补全
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
                  _buildDynamicCustomGroup_sample("dynamic_assets_sample_2"),
                ],
              ),

              // ----------------- [下标 3] 标签面板 D: 包气带 -----------------
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
              ),

              // ----------------- [下标 4] 标签面板 E: 风化壳 -----------------
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
              ),

              // ----------------- [下标 5] 标签面板 F: 成土母岩 -----------------
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: _buildInput('成土母岩岩性')),
                      SizedBox(width: 8),
                      Expanded(child: _buildInput('成土母岩颜色')),
                    ],
                  ),
                  _buildDynamicCustomGroup_sample("dynamic_assets_sample_5"),
                ],
              ),

              // ----------------- [下标 6] 标签面板 G: 水 -----------------
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDynamicCustomGroup_sample("dynamic_assets_sample_6"),
                ],
              ),
            ],
          ),
        ],
      ),

      // ================= 模块 4: 采样与影像资料 =================
      ExpansionTile(
        initiallyExpanded: true,
        maintainState: true, // ⭐ 新增：保持状态，收起不销毁内存
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
        maintainState: true, // ⭐ 新增：保持状态，收起不销毁内存
        title: Text('填表人员记录', style: TextStyle(fontWeight: FontWeight.bold)),
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
    ];
  }

  // ▶ 模板3：林草调查表_乔木
  List<Widget> _buildTemplate3() {
    return [
      ExpansionTile(
        initiallyExpanded: true,
        maintainState: true, // ⭐ 新增：保持状态，收起不销毁内存
        title: Text('样方取样模块', style: TextStyle(fontWeight: FontWeight.bold)),
        children: [_buildPhotoField('林草样方照片', '林草样方照片')],
      ),
      ExpansionTile(
        initiallyExpanded: true,
        maintainState: true, // ⭐ 新增：保持状态，收起不销毁内存
        title: Text('样方记录模块', style: TextStyle(fontWeight: FontWeight.bold)),
        children: [
          Text(''),
          Row(
            children: [
              Expanded(flex: 2, child: _buildAutoBox('样地号')),
              SizedBox(width: 8),
              Expanded(child: _buildDropdown('样地面积', ['20*20(m)', '30*30(m)'])),
            ],
          ),
          Row(
            children: [
              Expanded(child: _buildDropdown('森林起源', ['天然林', '人工林', '次生林'])),
              SizedBox(width: 8),
              Expanded(
                child: _buildDropdown('植被类型', [
                  '栽培植被',
                  '针叶林',
                  '阔叶林',
                  '草甸',
                  '沼泽',
                  '灌丛',
                  '针阔叶混交林',
                  '草原',
                  '高山植被',
                  '无植被地段',
                  '荒漠',
                  '草丛',
                ]),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(child: _buildInput('植被总盖度%')),
              SizedBox(width: 8),
              Expanded(child: _buildInput('林分郁闭度%')),
            ],
          ),
          _buildInput('优势树种'),
          Row(
            children: [
              Expanded(child: _buildInput('平均年龄')),
              SizedBox(width: 8),
              Expanded(child: _buildInput('平均树高(m)')),
              SizedBox(width: 8),
              Expanded(child: _buildInput('平均胸径(cm)')),
            ],
          ),
          _buildInput('根系发育深度'),
          _buildInput('林草样方总体描述'),
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
      SizedBox(height: 50),
    ];
  }

  // ▶ 模板4：林草调查表_灌木
  List<Widget> _buildTemplate4() {
    return [
      ExpansionTile(
        initiallyExpanded: true,
        maintainState: true, // ⭐ 新增：保持状态，收起不销毁内存
        title: Text('样方登记模块', style: TextStyle(fontWeight: FontWeight.bold)),
        children: [
          ExpansionTile(
            initiallyExpanded: true,
            maintainState: true, // ⭐ 新增：保持状态，收起不销毁内存
            title: Text(
              '样方取样模块',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            children: [_buildPhotoField('林草样方照片', '林草样方照片')],
          ),
          ExpansionTile(
            initiallyExpanded: true,
            maintainState: true, // ⭐ 新增：保持状态，收起不销毁内存
            title: Text(
              '样方记录模块',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            children: [
              Text(''),
              Row(
                children: [
                  Expanded(flex: 2, child: _buildAutoBox('样方号')),
                  SizedBox(width: 8),
                  Expanded(child: _buildAutoBox('灌木样方面积')),
                ],
              ),
              Row(
                children: [
                  Expanded(child: _buildInput('优势种')),
                  SizedBox(width: 8),
                  Expanded(child: _buildInput('覆盖度%')),
                  SizedBox(width: 8),
                  Expanded(child: _buildInput('平均高(m)')),
                ],
              ),
              _buildInput('根系发育深度'),
              _buildInput('林草样方总体描述'),
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
        ],
      ),
      SizedBox(height: 50),
    ];
  }

  // ▶ 模板5：林草调查表_草木
  List<Widget> _buildTemplate5() {
    return [
      ExpansionTile(
        initiallyExpanded: true,
        maintainState: true, // ⭐ 新增：保持状态，收起不销毁内存
        title: Text('样方登记模块', style: TextStyle(fontWeight: FontWeight.bold)),
        children: [
          ExpansionTile(
            initiallyExpanded: true,
            maintainState: true, // ⭐ 新增：保持状态，收起不销毁内存
            title: Text(
              '样方取样模块',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            children: [_buildPhotoField('林草样方照片', '林草样方照片')],
          ),
          ExpansionTile(
            initiallyExpanded: true,
            maintainState: true, // ⭐ 新增：保持状态，收起不销毁内存
            title: Text(
              '样方记录模块',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            children: [
              Text(''),
              Row(
                children: [
                  Expanded(flex: 2, child: _buildAutoBox('样方号')),
                  SizedBox(width: 8),
                  Expanded(child: _buildAutoBox('草木样方面积')),
                ],
              ),
              Row(
                children: [
                  Expanded(child: _buildInput('优势种')),
                  SizedBox(width: 8),
                  Expanded(child: _buildInput('覆盖度%')),
                  SizedBox(width: 8),
                  Expanded(child: _buildInput('平均高(m)')),
                ],
              ),
              _buildInput('根系发育深度'),
              _buildInput('林草样方总体描述'),
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
        ],
      ),
      SizedBox(height: 50),
    ];
  }

  // ============== 页面构建 ==============
  @override
  Widget build(BuildContext context) {
    // 通过 widget.templateType 判断使用什么标题，后续你可以使用 if-else 渲染整块不同的树
    String title = "测量记录表";
    if (widget.templateType == '1') title = "生态地质调查点记录表";
    if (widget.templateType == '2') title = "生态地质垂直剖面测量记录表";
    if (widget.templateType == '3') title = "乔木_生态地质垂直剖面测量点林草调查表";
    if (widget.templateType == '4') title = "灌木_生态地质垂直剖面测量点林草调查表";
    if (widget.templateType == '5') title = "草木_生态地质垂直剖面测量点林草调查表";

    // 动态分发 Body 块
    List<Widget> formChildren;
    if (widget.templateType == '1') {
      formChildren = _buildTemplate1();
    } else if (widget.templateType == '2') {
      formChildren = _buildTemplate2();
    } else if (widget.templateType == '3') {
      formChildren = _buildTemplate3();
    } else if (widget.templateType == '4') {
      formChildren = _buildTemplate4();
    } else {
      formChildren = _buildTemplate5();
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        titleTextStyle: TextStyle(color: Colors.black, fontSize: 18),
        backgroundColor: Colors.green,
        actions: [
          TextButton(
            onPressed: () {
              // 进行表单校验后退出并返回 formData 给调用者
              _submitForm();
              // Navigator.pop(context, _formData);
            },
            child: Text(
              "完成提交",
              style: TextStyle(color: Colors.white, fontSize: 15),
            ),
          ),
        ],
      ),
      // 外层使用 ListView 避免键盘遮挡报错
      body: ListView(padding: EdgeInsets.all(12), children: formChildren),
    );
  }
}
