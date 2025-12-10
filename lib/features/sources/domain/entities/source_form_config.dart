import 'package:my_nas/features/sources/domain/entities/source_entity.dart';

/// 表单字段类型
enum SourceFormFieldType {
  text,
  password,
  number,
  url,
  toggle,
  select,
}

/// 表单字段配置
class SourceFormField {
  const SourceFormField({
    required this.key,
    required this.label,
    this.placeholder,
    this.helpText,
    this.required = true,
    this.type = SourceFormFieldType.text,
    this.defaultValue,
    this.options,
    this.validator,
    this.visibilityCondition,
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
  final SourceFormFieldType type;

  /// 默认值
  final String? defaultValue;

  /// 选项列表（用于下拉选择）
  final List<String>? options;

  /// 自定义验证器
  final String? Function(String?)? validator;

  /// 可见性条件（基于其他字段的值）
  final bool Function(Map<String, dynamic>)? visibilityCondition;
}

/// 表单分组配置
class SourceFormSection {
  const SourceFormSection({
    required this.title,
    required this.fields,
    this.collapsible = false,
    this.defaultExpanded = true,
    this.description,
  });

  /// 分组标题
  final String title;

  /// 分组描述
  final String? description;

  /// 分组内的字段
  final List<SourceFormField> fields;

  /// 是否可折叠
  final bool collapsible;

  /// 默认是否展开
  final bool defaultExpanded;
}

/// 源类型表单配置
class SourceFormConfig {
  const SourceFormConfig({
    required this.type,
    required this.sections,
    this.testConnectionSupported = true,
    this.oauthRequired = false,
  });

  /// 源类型
  final SourceType type;

  /// 表单分组
  final List<SourceFormSection> sections;

  /// 是否支持测试连接
  final bool testConnectionSupported;

  /// 是否需要 OAuth 认证流程
  final bool oauthRequired;

  /// 获取指定源类型的表单配置
  static SourceFormConfig forType(SourceType type) {
    switch (type) {
      // === NAS 设备 ===
      case SourceType.synology:
        return _getSynologyConfig();
      case SourceType.qnap:
        return _getQnapConfig();
      case SourceType.ugreen:
        return _getUgreenConfig();
      case SourceType.fnos:
        return _getFnosConfig();

      // === 通用协议 ===
      case SourceType.webdav:
        return _getWebdavConfig();
      case SourceType.smb:
        return _getSmbConfig();

      // === 本地存储 ===
      case SourceType.local:
        return _getLocalConfig();

      // === 下载工具 ===
      case SourceType.qbittorrent:
        return _getQbittorrentConfig();
      case SourceType.transmission:
        return _getTransmissionConfig();
      case SourceType.aria2:
        return _getAria2Config();

      // === 媒体追踪 ===
      case SourceType.trakt:
        return _getTraktConfig();

      // === 媒体管理 ===
      case SourceType.nastool:
        return _getNastoolConfig();
      case SourceType.moviepilot:
        return _getMoviepilotConfig();
      case SourceType.jellyfin:
        return _getJellyfinConfig();
      case SourceType.emby:
        return _getEmbyConfig();
      case SourceType.plex:
        return _getPlexConfig();
    }
  }

  // === NAS 设备配置 ===

  static SourceFormConfig _getSynologyConfig() => SourceFormConfig(
      type: SourceType.synology,
      sections: [
        _basicInfoSection(),
        SourceFormSection(
          title: '连接配置',
          fields: [
            const SourceFormField(
              key: 'host',
              label: '主机地址',
              placeholder: '192.168.1.100 或 your-nas.synology.me',
              helpText: '支持 IP 地址或 QuickConnect ID',
            ),
            SourceFormField(
              key: 'port',
              label: '端口',
              type: SourceFormFieldType.number,
              defaultValue: SourceType.synology.defaultPort.toString(),
            ),
            const SourceFormField(
              key: 'useSsl',
              label: '使用 HTTPS',
              type: SourceFormFieldType.toggle,
              defaultValue: 'true',
            ),
          ],
        ),
        _credentialSection(),
        _advancedSection(),
      ],
    );

  static SourceFormConfig _getQnapConfig() => SourceFormConfig(
      type: SourceType.qnap,
      sections: [
        _basicInfoSection(),
        SourceFormSection(
          title: '连接配置',
          fields: [
            const SourceFormField(
              key: 'host',
              label: '主机地址',
              placeholder: '192.168.1.100',
            ),
            SourceFormField(
              key: 'port',
              label: '端口',
              type: SourceFormFieldType.number,
              defaultValue: SourceType.qnap.defaultPort.toString(),
            ),
            const SourceFormField(
              key: 'useSsl',
              label: '使用 HTTPS',
              type: SourceFormFieldType.toggle,
              defaultValue: 'false',
            ),
          ],
        ),
        _credentialSection(),
        _advancedSection(),
      ],
    );

  static SourceFormConfig _getUgreenConfig() => SourceFormConfig(
      type: SourceType.ugreen,
      sections: [
        _basicInfoSection(),
        SourceFormSection(
          title: '连接配置',
          fields: [
            const SourceFormField(
              key: 'host',
              label: '主机地址',
              placeholder: '192.168.1.100',
            ),
            SourceFormField(
              key: 'port',
              label: '端口',
              type: SourceFormFieldType.number,
              defaultValue: SourceType.ugreen.defaultPort.toString(),
            ),
            const SourceFormField(
              key: 'useSsl',
              label: '使用 HTTPS',
              type: SourceFormFieldType.toggle,
              defaultValue: 'false',
            ),
          ],
        ),
        _credentialSection(),
        _advancedSection(),
      ],
    );

  static SourceFormConfig _getFnosConfig() => SourceFormConfig(
      type: SourceType.fnos,
      sections: [
        _basicInfoSection(),
        SourceFormSection(
          title: '连接配置',
          fields: [
            const SourceFormField(
              key: 'host',
              label: '主机地址',
              placeholder: '192.168.1.100',
            ),
            SourceFormField(
              key: 'port',
              label: '端口',
              type: SourceFormFieldType.number,
              defaultValue: SourceType.fnos.defaultPort.toString(),
            ),
            const SourceFormField(
              key: 'useSsl',
              label: '使用 HTTPS',
              type: SourceFormFieldType.toggle,
              defaultValue: 'false',
            ),
          ],
        ),
        _credentialSection(),
        _advancedSection(),
      ],
    );

  // === 通用协议配置 ===

  static SourceFormConfig _getWebdavConfig() => SourceFormConfig(
      type: SourceType.webdav,
      sections: [
        _basicInfoSection(),
        SourceFormSection(
          title: '连接配置',
          fields: [
            const SourceFormField(
              key: 'host',
              label: '服务器地址',
              placeholder: 'webdav.example.com',
              helpText: '不需要包含协议前缀（http/https）',
            ),
            SourceFormField(
              key: 'port',
              label: '端口',
              type: SourceFormFieldType.number,
              defaultValue: SourceType.webdav.defaultPort.toString(),
            ),
            const SourceFormField(
              key: 'useSsl',
              label: '使用 HTTPS',
              type: SourceFormFieldType.toggle,
              defaultValue: 'true',
            ),
            const SourceFormField(
              key: 'basePath',
              label: '基础路径',
              placeholder: '/dav 或 /webdav',
              required: false,
              helpText: '可选，WebDAV 服务的基础路径',
            ),
          ],
        ),
        _credentialSection(),
        _advancedSection(),
      ],
    );

  static SourceFormConfig _getSmbConfig() => SourceFormConfig(
      type: SourceType.smb,
      sections: [
        _basicInfoSection(),
        SourceFormSection(
          title: '连接配置',
          description: 'SMB 协议使用固定端口 445',
          fields: [
            const SourceFormField(
              key: 'host',
              label: '主机地址',
              placeholder: '192.168.1.100',
              helpText: '仅支持 IP 地址',
            ),
            const SourceFormField(
              key: 'shareName',
              label: '共享名称',
              placeholder: 'share',
              helpText: '要访问的共享文件夹名称',
            ),
          ],
        ),
        _credentialSection(),
        _advancedSection(),
      ],
    );

  // === 本地存储配置 ===

  static SourceFormConfig _getLocalConfig() => SourceFormConfig(
      type: SourceType.local,
      testConnectionSupported: false,
      sections: [
        SourceFormSection(
          title: '基本信息',
          fields: [
            const SourceFormField(
              key: 'name',
              label: '名称',
              placeholder: '本地存储',
              required: false,
            ),
          ],
        ),
        SourceFormSection(
          title: '存储位置',
          description: '选择要访问的本地文件夹',
          fields: [
            const SourceFormField(
              key: 'localPath',
              label: '文件夹路径',
              placeholder: '点击选择文件夹',
              helpText: '将自动请求存储权限',
            ),
          ],
        ),
      ],
    );

  // === 下载工具配置 ===

  static SourceFormConfig _getQbittorrentConfig() => SourceFormConfig(
      type: SourceType.qbittorrent,
      sections: [
        _basicInfoSection(),
        SourceFormSection(
          title: '连接配置',
          fields: [
            const SourceFormField(
              key: 'host',
              label: '主机地址',
              placeholder: '192.168.1.100',
            ),
            SourceFormField(
              key: 'port',
              label: '端口',
              type: SourceFormFieldType.number,
              defaultValue: SourceType.qbittorrent.defaultPort.toString(),
            ),
            const SourceFormField(
              key: 'useSsl',
              label: '使用 HTTPS',
              type: SourceFormFieldType.toggle,
              defaultValue: 'false',
            ),
          ],
        ),
        SourceFormSection(
          title: '认证方式',
          description: 'qBittorrent v5.2+ 支持 API Key 认证',
          fields: [
            const SourceFormField(
              key: 'authType',
              label: '认证类型',
              type: SourceFormFieldType.select,
              options: ['用户名密码', 'API Key'],
              defaultValue: '用户名密码',
            ),
            SourceFormField(
              key: 'username',
              label: '用户名',
              placeholder: 'admin',
              visibilityCondition: (values) =>
                  values['authType'] != 'API Key',
            ),
            SourceFormField(
              key: 'password',
              label: '密码',
              type: SourceFormFieldType.password,
              visibilityCondition: (values) =>
                  values['authType'] != 'API Key',
            ),
            SourceFormField(
              key: 'apiKey',
              label: 'API Key',
              type: SourceFormFieldType.password,
              placeholder: 'qbt_xxxxxxxxxxxxxxxxxxxxxxxx',
              helpText: '32 字符，以 qbt_ 开头',
              visibilityCondition: (values) =>
                  values['authType'] == 'API Key',
            ),
          ],
        ),
        _advancedSection(defaultAutoConnect: false),
      ],
    );

  static SourceFormConfig _getTransmissionConfig() => SourceFormConfig(
      type: SourceType.transmission,
      sections: [
        _basicInfoSection(),
        SourceFormSection(
          title: '连接配置',
          fields: [
            const SourceFormField(
              key: 'host',
              label: '主机地址',
              placeholder: '192.168.1.100',
            ),
            SourceFormField(
              key: 'port',
              label: '端口',
              type: SourceFormFieldType.number,
              defaultValue: SourceType.transmission.defaultPort.toString(),
            ),
            const SourceFormField(
              key: 'useSsl',
              label: '使用 HTTPS',
              type: SourceFormFieldType.toggle,
              defaultValue: 'false',
            ),
            const SourceFormField(
              key: 'rpcPath',
              label: 'RPC 路径',
              placeholder: '/transmission/rpc',
              defaultValue: '/transmission/rpc',
              required: false,
            ),
          ],
        ),
        _credentialSection(),
        _advancedSection(defaultAutoConnect: false),
      ],
    );

  static SourceFormConfig _getAria2Config() => SourceFormConfig(
      type: SourceType.aria2,
      sections: [
        _basicInfoSection(),
        SourceFormSection(
          title: '连接配置',
          fields: [
            const SourceFormField(
              key: 'host',
              label: '主机地址',
              placeholder: '192.168.1.100',
            ),
            SourceFormField(
              key: 'port',
              label: 'RPC 端口',
              type: SourceFormFieldType.number,
              defaultValue: SourceType.aria2.defaultPort.toString(),
            ),
            const SourceFormField(
              key: 'useSsl',
              label: '使用 HTTPS',
              type: SourceFormFieldType.toggle,
              defaultValue: 'false',
            ),
          ],
        ),
        const SourceFormSection(
          title: '认证信息',
          fields: [
            SourceFormField(
              key: 'rpcSecret',
              label: 'RPC 密钥',
              type: SourceFormFieldType.password,
              placeholder: '你的 RPC 密钥',
              helpText: 'aria2 配置文件中的 rpc-secret 值',
              required: false,
            ),
          ],
        ),
        _advancedSection(defaultAutoConnect: false),
      ],
    );

  // === 媒体追踪配置 ===

  static SourceFormConfig _getTraktConfig() => SourceFormConfig(
      type: SourceType.trakt,
      oauthRequired: true,
      sections: [
        _basicInfoSection(),
        const SourceFormSection(
          title: 'OAuth 配置',
          description: '请在 trakt.tv 创建应用获取以下信息',
          fields: [
            SourceFormField(
              key: 'clientId',
              label: 'Client ID',
              placeholder: '从 Trakt 应用设置获取',
            ),
            SourceFormField(
              key: 'clientSecret',
              label: 'Client Secret',
              type: SourceFormFieldType.password,
            ),
          ],
        ),
        const SourceFormSection(
          title: '同步设置',
          collapsible: true,
          defaultExpanded: false,
          fields: [
            SourceFormField(
              key: 'syncWatchedHistory',
              label: '同步观看历史',
              type: SourceFormFieldType.toggle,
              defaultValue: 'true',
            ),
            SourceFormField(
              key: 'syncRatings',
              label: '同步评分',
              type: SourceFormFieldType.toggle,
              defaultValue: 'true',
            ),
            SourceFormField(
              key: 'syncWatchlist',
              label: '同步待看列表',
              type: SourceFormFieldType.toggle,
              defaultValue: 'true',
            ),
          ],
        ),
      ],
    );

  // === 媒体管理配置 ===

  static SourceFormConfig _getNastoolConfig() => SourceFormConfig(
      type: SourceType.nastool,
      sections: [
        _basicInfoSection(),
        SourceFormSection(
          title: '连接配置',
          fields: [
            const SourceFormField(
              key: 'host',
              label: '主机地址',
              placeholder: '192.168.1.100',
            ),
            SourceFormField(
              key: 'port',
              label: '端口',
              type: SourceFormFieldType.number,
              defaultValue: SourceType.nastool.defaultPort.toString(),
            ),
            const SourceFormField(
              key: 'useSsl',
              label: '使用 HTTPS',
              type: SourceFormFieldType.toggle,
              defaultValue: 'false',
            ),
          ],
        ),
        const SourceFormSection(
          title: '认证信息',
          fields: [
            SourceFormField(
              key: 'apiToken',
              label: 'API Token',
              type: SourceFormFieldType.password,
              helpText: '在 NASTool 设置中生成',
            ),
          ],
        ),
        _advancedSection(defaultAutoConnect: false),
      ],
    );

  static SourceFormConfig _getMoviepilotConfig() => SourceFormConfig(
      type: SourceType.moviepilot,
      sections: [
        _basicInfoSection(),
        SourceFormSection(
          title: '连接配置',
          fields: [
            const SourceFormField(
              key: 'host',
              label: '主机地址',
              placeholder: '192.168.1.100',
            ),
            SourceFormField(
              key: 'port',
              label: '端口',
              type: SourceFormFieldType.number,
              defaultValue: SourceType.moviepilot.defaultPort.toString(),
            ),
            const SourceFormField(
              key: 'useSsl',
              label: '使用 HTTPS',
              type: SourceFormFieldType.toggle,
              defaultValue: 'false',
            ),
          ],
        ),
        const SourceFormSection(
          title: '认证信息',
          fields: [
            SourceFormField(
              key: 'apiToken',
              label: 'API Token',
              type: SourceFormFieldType.password,
              helpText: '在 MoviePilot 设置中获取',
            ),
          ],
        ),
        _advancedSection(defaultAutoConnect: false),
      ],
    );

  static SourceFormConfig _getJellyfinConfig() => SourceFormConfig(
      type: SourceType.jellyfin,
      sections: [
        _basicInfoSection(),
        SourceFormSection(
          title: '连接配置',
          fields: [
            const SourceFormField(
              key: 'host',
              label: '服务器地址',
              placeholder: '192.168.1.100',
            ),
            SourceFormField(
              key: 'port',
              label: '端口',
              type: SourceFormFieldType.number,
              defaultValue: SourceType.jellyfin.defaultPort.toString(),
            ),
            const SourceFormField(
              key: 'useSsl',
              label: '使用 HTTPS',
              type: SourceFormFieldType.toggle,
              defaultValue: 'false',
            ),
          ],
        ),
        _credentialSection(),
        _advancedSection(defaultAutoConnect: false),
      ],
    );

  static SourceFormConfig _getEmbyConfig() => SourceFormConfig(
      type: SourceType.emby,
      sections: [
        _basicInfoSection(),
        SourceFormSection(
          title: '连接配置',
          fields: [
            const SourceFormField(
              key: 'host',
              label: '服务器地址',
              placeholder: '192.168.1.100',
            ),
            SourceFormField(
              key: 'port',
              label: '端口',
              type: SourceFormFieldType.number,
              defaultValue: SourceType.emby.defaultPort.toString(),
            ),
            const SourceFormField(
              key: 'useSsl',
              label: '使用 HTTPS',
              type: SourceFormFieldType.toggle,
              defaultValue: 'false',
            ),
          ],
        ),
        const SourceFormSection(
          title: '认证信息',
          description: '使用 API Key 或用户名密码认证',
          fields: [
            SourceFormField(
              key: 'apiKey',
              label: 'API Key',
              type: SourceFormFieldType.password,
              helpText: '在 Emby 控制面板中生成',
              required: false,
            ),
            SourceFormField(
              key: 'username',
              label: '用户名',
              required: false,
            ),
            SourceFormField(
              key: 'password',
              label: '密码',
              type: SourceFormFieldType.password,
              required: false,
            ),
          ],
        ),
        _advancedSection(defaultAutoConnect: false),
      ],
    );

  static SourceFormConfig _getPlexConfig() => SourceFormConfig(
      type: SourceType.plex,
      sections: [
        _basicInfoSection(),
        SourceFormSection(
          title: '连接配置',
          fields: [
            const SourceFormField(
              key: 'host',
              label: '服务器地址',
              placeholder: '192.168.1.100',
            ),
            SourceFormField(
              key: 'port',
              label: '端口',
              type: SourceFormFieldType.number,
              defaultValue: SourceType.plex.defaultPort.toString(),
            ),
            const SourceFormField(
              key: 'useSsl',
              label: '使用 HTTPS',
              type: SourceFormFieldType.toggle,
              defaultValue: 'false',
            ),
          ],
        ),
        const SourceFormSection(
          title: '认证信息',
          fields: [
            SourceFormField(
              key: 'plexToken',
              label: 'Plex Token',
              type: SourceFormFieldType.password,
              helpText: '从 Plex Web 获取 X-Plex-Token',
            ),
          ],
        ),
        _advancedSection(defaultAutoConnect: false),
      ],
    );

  // === 通用分组模板 ===

  static SourceFormSection _basicInfoSection() => const SourceFormSection(
      title: '基本信息',
      fields: [
        SourceFormField(
          key: 'name',
          label: '名称',
          placeholder: '自定义名称',
          required: false,
          helpText: '留空将使用主机地址作为名称',
        ),
      ],
    );

  static SourceFormSection _credentialSection() => const SourceFormSection(
      title: '账户信息',
      fields: [
        SourceFormField(
          key: 'username',
          label: '用户名',
        ),
        SourceFormField(
          key: 'password',
          label: '密码',
          type: SourceFormFieldType.password,
        ),
      ],
    );

  static SourceFormSection _advancedSection({
    bool defaultAutoConnect = true,
  }) => SourceFormSection(
      title: '高级选项',
      collapsible: true,
      defaultExpanded: false,
      fields: [
        SourceFormField(
          key: 'autoConnect',
          label: '启动时自动连接',
          type: SourceFormFieldType.toggle,
          defaultValue: defaultAutoConnect.toString(),
        ),
        const SourceFormField(
          key: 'rememberDevice',
          label: '记住设备（跳过二次验证）',
          type: SourceFormFieldType.toggle,
          defaultValue: 'false',
        ),
      ],
    );
}
