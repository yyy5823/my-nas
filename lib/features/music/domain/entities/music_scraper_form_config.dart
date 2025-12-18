import 'package:my_nas/features/music/domain/entities/music_scraper_source.dart';

/// 音乐刮削源表单字段类型
enum MusicScraperFormFieldType {
  text,
  password,
  number,
  url,
  toggle,
}

/// 音乐刮削源表单字段配置
class MusicScraperFormField {
  const MusicScraperFormField({
    required this.key,
    required this.label,
    this.placeholder,
    this.helpText,
    this.required = true,
    this.type = MusicScraperFormFieldType.text,
    this.defaultValue,
    this.validator,
  });

  /// 字段键名
  final String key;

  /// 字段标签
  final String label;

  /// 占位文本
  final String? placeholder;

  /// 帮助文本
  final String? helpText;

  /// 是否必填
  final bool required;

  /// 字段类型
  final MusicScraperFormFieldType type;

  /// 默认值
  final String? defaultValue;

  /// 自定义验证器
  final String? Function(String?)? validator;
}

/// 音乐刮削源表单分组配置
class MusicScraperFormSection {
  const MusicScraperFormSection({
    required this.title,
    required this.fields,
    this.description,
  });

  /// 分组标题
  final String title;

  /// 分组描述
  final String? description;

  /// 分组内的字段
  final List<MusicScraperFormField> fields;
}

/// 音乐刮削源类型表单配置
class MusicScraperFormConfig {
  const MusicScraperFormConfig({
    required this.type,
    required this.sections,
    this.testConnectionSupported = true,
  });

  /// 刮削源类型
  final MusicScraperType type;

  /// 表单分组
  final List<MusicScraperFormSection> sections;

  /// 是否支持测试连接
  final bool testConnectionSupported;

  /// 获取指定刮削源类型的表单配置
  static MusicScraperFormConfig forType(MusicScraperType type) => switch (type) {
        MusicScraperType.musicBrainz => _getMusicBrainzConfig(),
        MusicScraperType.acoustId => _getAcoustIdConfig(),
        MusicScraperType.coverArtArchive => _getCoverArtArchiveConfig(),
        MusicScraperType.lastFm => _getLastFmConfig(),
        MusicScraperType.neteaseMusic => _getNeteaseConfig(),
        MusicScraperType.qqMusic => _getQQMusicConfig(),
        MusicScraperType.genius => _getGeniusConfig(),
        MusicScraperType.musicTagWeb => _getMusicTagWebConfig(),
      };

  // === MusicBrainz 配置 ===
  static MusicScraperFormConfig _getMusicBrainzConfig() =>
      const MusicScraperFormConfig(
        type: MusicScraperType.musicBrainz,
        sections: [
          MusicScraperFormSection(
            title: '基本信息',
            fields: [
              MusicScraperFormField(
                key: 'name',
                label: '名称',
                placeholder: 'MusicBrainz',
                required: false,
                helpText: '自定义名称，留空使用默认名称',
              ),
            ],
          ),
          MusicScraperFormSection(
            title: '说明',
            description: 'MusicBrainz 是开放的音乐数据库，无需认证即可使用\n'
                '为遵守使用规则，请求间隔不低于 1 秒',
            fields: [],
          ),
        ],
      );

  // === AcoustID 配置 ===
  static MusicScraperFormConfig _getAcoustIdConfig() =>
      const MusicScraperFormConfig(
        type: MusicScraperType.acoustId,
        sections: [
          MusicScraperFormSection(
            title: '基本信息',
            fields: [
              MusicScraperFormField(
                key: 'name',
                label: '名称',
                placeholder: 'AcoustID',
                required: false,
                helpText: '自定义名称，留空使用默认名称',
              ),
            ],
          ),
          MusicScraperFormSection(
            title: 'API 配置',
            description: '在 acoustid.org 免费注册获取 API Key',
            fields: [
              MusicScraperFormField(
                key: 'apiKey',
                label: 'API Key',
                type: MusicScraperFormFieldType.password,
                placeholder: '输入 AcoustID API Key',
                helpText: '用于声纹识别查询',
              ),
            ],
          ),
        ],
      );

  // === Cover Art Archive 配置 ===
  static MusicScraperFormConfig _getCoverArtArchiveConfig() =>
      const MusicScraperFormConfig(
        type: MusicScraperType.coverArtArchive,
        sections: [
          MusicScraperFormSection(
            title: '基本信息',
            fields: [
              MusicScraperFormField(
                key: 'name',
                label: '名称',
                placeholder: 'Cover Art Archive',
                required: false,
                helpText: '自定义名称，留空使用默认名称',
              ),
            ],
          ),
          MusicScraperFormSection(
            title: '说明',
            description: 'Cover Art Archive 是 MusicBrainz 的封面数据库\n'
                '无需认证即可使用',
            fields: [],
          ),
        ],
      );

  // === Last.fm 配置 ===
  static MusicScraperFormConfig _getLastFmConfig() =>
      const MusicScraperFormConfig(
        type: MusicScraperType.lastFm,
        sections: [
          MusicScraperFormSection(
            title: '基本信息',
            fields: [
              MusicScraperFormField(
                key: 'name',
                label: '名称',
                placeholder: 'Last.fm',
                required: false,
                helpText: '自定义名称，留空使用默认名称',
              ),
            ],
          ),
          MusicScraperFormSection(
            title: 'API 配置',
            description: '在 last.fm/api 申请免费的 API Key',
            fields: [
              MusicScraperFormField(
                key: 'apiKey',
                label: 'API Key',
                type: MusicScraperFormFieldType.password,
                placeholder: '输入 Last.fm API Key',
                helpText: '用于获取元数据和封面',
              ),
            ],
          ),
        ],
      );

  // === 网易云音乐配置 ===
  static MusicScraperFormConfig _getNeteaseConfig() =>
      const MusicScraperFormConfig(
        type: MusicScraperType.neteaseMusic,
        sections: [
          MusicScraperFormSection(
            title: '基本信息',
            fields: [
              MusicScraperFormField(
                key: 'name',
                label: '名称',
                placeholder: '网易云音乐',
                required: false,
                helpText: '自定义名称，留空使用默认名称',
              ),
            ],
          ),
          MusicScraperFormSection(
            title: 'Cookie 配置（可选）',
            description: '登录后的 Cookie 可以获取更多歌词\n'
                '不提供 Cookie 也可以使用基本功能',
            fields: [
              MusicScraperFormField(
                key: 'cookie',
                label: 'Cookie',
                type: MusicScraperFormFieldType.password,
                placeholder: '从浏览器复制登录后的 Cookie',
                required: false,
                helpText: '登录网易云音乐后，从浏览器开发者工具获取',
              ),
            ],
          ),
        ],
      );

  // === QQ音乐配置 ===
  static MusicScraperFormConfig _getQQMusicConfig() =>
      const MusicScraperFormConfig(
        type: MusicScraperType.qqMusic,
        sections: [
          MusicScraperFormSection(
            title: '基本信息',
            fields: [
              MusicScraperFormField(
                key: 'name',
                label: '名称',
                placeholder: 'QQ音乐',
                required: false,
                helpText: '自定义名称，留空使用默认名称',
              ),
            ],
          ),
          MusicScraperFormSection(
            title: 'Cookie 配置（可选）',
            description: '登录后的 Cookie 可以获取更多歌词\n'
                '不提供 Cookie 也可以使用基本功能',
            fields: [
              MusicScraperFormField(
                key: 'cookie',
                label: 'Cookie',
                type: MusicScraperFormFieldType.password,
                placeholder: '从浏览器复制登录后的 Cookie',
                required: false,
                helpText: '登录 QQ 音乐后，从浏览器开发者工具获取',
              ),
            ],
          ),
        ],
      );

  // === Genius 配置 ===
  static MusicScraperFormConfig _getGeniusConfig() =>
      const MusicScraperFormConfig(
        type: MusicScraperType.genius,
        sections: [
          MusicScraperFormSection(
            title: '基本信息',
            fields: [
              MusicScraperFormField(
                key: 'name',
                label: '名称',
                placeholder: 'Genius',
                required: false,
                helpText: '自定义名称，留空使用默认名称',
              ),
            ],
          ),
          MusicScraperFormSection(
            title: 'API 配置',
            description: '在 genius.com/api-clients 申请 API Token',
            fields: [
              MusicScraperFormField(
                key: 'apiKey',
                label: 'Access Token',
                type: MusicScraperFormFieldType.password,
                placeholder: '输入 Genius Access Token',
                helpText: '用于获取歌词和元数据（主要为英文歌曲）',
              ),
            ],
          ),
        ],
      );

  // === Music Tag Web 配置 ===
  static MusicScraperFormConfig _getMusicTagWebConfig() =>
      const MusicScraperFormConfig(
        type: MusicScraperType.musicTagWeb,
        sections: [
          MusicScraperFormSection(
            title: '基本信息',
            fields: [
              MusicScraperFormField(
                key: 'name',
                label: '名称',
                placeholder: 'Music Tag Web',
                required: false,
                helpText: '自定义名称，留空使用默认名称',
              ),
            ],
          ),
          MusicScraperFormSection(
            title: '服务器配置',
            description: '自托管的音乐刮削服务，支持元数据、封面和歌词',
            fields: [
              MusicScraperFormField(
                key: 'serverUrl',
                label: '服务器地址',
                type: MusicScraperFormFieldType.url,
                placeholder: 'http://192.168.1.100:8080',
                helpText: 'Music Tag Web 服务器的完整地址',
              ),
            ],
          ),
        ],
      );

  /// 从表单数据创建刮削源实体
  static MusicScraperSourceEntity createSourceFromFormData(
    MusicScraperType type,
    Map<String, dynamic> formData,
  ) {
    final name = formData['name'] as String?;
    final serverUrl = formData['serverUrl'] as String?;

    return MusicScraperSourceEntity(
      name: (name?.isNotEmpty ?? false) ? name! : type.displayName,
      type: type,
      apiKey: formData['apiKey'] as String?,
      cookie: formData['cookie'] as String?,
      extraConfig: serverUrl != null && serverUrl.isNotEmpty
          ? {'serverUrl': serverUrl}
          : null,
      isEnabled: true,
      priority: 0, // 将由 manager 设置
    );
  }

  /// 从刮削源实体提取表单数据
  static Map<String, dynamic> extractFormDataFromSource(
          MusicScraperSourceEntity source) =>
      {
        'name': source.name != source.type.displayName ? source.name : '',
        'apiKey': source.apiKey ?? '',
        'cookie': source.cookie ?? '',
        'serverUrl': source.serverUrl ?? '',
      };
}
