# MyNAS 账号与激活码系统设计文档

> 版本: 1.0.0
> 日期: 2024-12-13
> 状态: 设计阶段

---

## 目录

1. [概述](#1-概述)
2. [系统架构](#2-系统架构)
3. [用户等级体系](#3-用户等级体系)
4. [激活方式设计](#4-激活方式设计)
5. [数据库设计](#5-数据库设计)
6. [API 接口设计](#6-api-接口设计)
7. [客户端改造方案](#7-客户端改造方案)
8. [后端扩展方案](#8-后端扩展方案)
9. [安全与防破解](#9-安全与防破解)
10. [功能权限矩阵](#10-功能权限矩阵)
11. [实施计划](#11-实施计划)
12. [附录](#附录)

---

## 1. 概述

### 1.1 背景

MyNAS 是一款跨平台 NAS 客户端应用，需要引入账号体系和激活码系统以实现：
- 功能分级变现
- 用户数据云同步
- 跨设备使用管理
- 用户行为分析

### 1.2 设计目标

| 目标 | 描述 |
|------|------|
| 双模式激活 | 支持在线激活（账号登录）和离线激活（邮箱+激活码） |
| 功能分级 | 普通用户、VIP、SVIP、管理员四个等级 |
| 设备管理 | 激活码绑定设备，超限自动淘汰旧设备 |
| 安全防护 | 多层防破解机制，保护商业利益 |
| 系统复用 | 复用现有 allbs-admin 后台管理系统 |

### 1.3 技术栈

| 层级 | 技术 |
|------|------|
| 客户端 | Flutter 3.10+ / Dart 3.0+ / Riverpod |
| 后端 | Spring Boot 3.5.3 / Spring Security OAuth2 |
| 数据库 | MySQL 8.0 / Redis |
| 认证 | JWT / OAuth2 / RSA 签名 |

---

## 2. 系统架构

### 2.1 整体架构图

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              MyNAS 客户端                                    │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        │
│  │   视频模块   │  │   音乐模块   │  │   照片模块   │  │   ...更多    │        │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘        │
│         │                │                │                │                │
│         └────────────────┴────────────────┴────────────────┘                │
│                                   │                                         │
│                    ┌──────────────┴──────────────┐                          │
│                    │      FeatureGuard 权限守卫    │                          │
│                    └──────────────┬──────────────┘                          │
│                                   │                                         │
│         ┌─────────────────────────┼─────────────────────────┐              │
│         │                         │                         │              │
│  ┌──────┴──────┐          ┌───────┴───────┐         ┌───────┴───────┐      │
│  │ AuthProvider │          │LicenseProvider│         │ DeviceService │      │
│  │  (账号状态)   │          │  (授权状态)    │         │  (设备指纹)   │      │
│  └──────┬──────┘          └───────┬───────┘         └───────────────┘      │
│         │                         │                                         │
│         └────────────┬────────────┘                                         │
│                      │                                                      │
│         ┌────────────┴────────────┐                                         │
│         │    LicenseValidator     │                                         │
│         │  (本地验证 + 在线验证)   │                                         │
│         └────────────┬────────────┘                                         │
│                      │                                                      │
│    ┌─────────────────┼─────────────────┐                                    │
│    │                 │                 │                                    │
│    ▼                 ▼                 ▼                                    │
│ ┌──────┐        ┌──────┐         ┌──────┐                                   │
│ │ Hive │        │Secure│         │SQLite│                                   │
│ │Cache │        │Storage│        │ DB   │                                   │
│ └──────┘        └──────┘         └──────┘                                   │
└─────────────────────────────────────────────────────────────────────────────┘
                                   │
                                   │ HTTPS
                                   ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           allbs-admin 后端                                   │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                     Spring Security OAuth2                           │   │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐            │   │
│  │  │ Password │  │  OAuth2  │  │  Device  │  │ Refresh  │            │   │
│  │  │  Grant   │  │  Code    │  │   Code   │  │  Token   │            │   │
│  │  └──────────┘  └──────────┘  └──────────┘  └──────────┘            │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        │
│  │  用户服务    │  │  激活码服务  │  │  设备服务    │  │  同步服务    │        │
│  │ UserService │  │LicenseService│  │DeviceService│  │ SyncService │        │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘        │
│         │                │                │                │                │
│         └────────────────┴────────────────┴────────────────┘                │
│                                   │                                         │
│                    ┌──────────────┴──────────────┐                          │
│                    │         MyBatis-Plus         │                          │
│                    └──────────────┬──────────────┘                          │
│                                   │                                         │
│              ┌────────────────────┼────────────────────┐                    │
│              ▼                    ▼                    ▼                    │
│         ┌────────┐           ┌────────┐          ┌────────┐                 │
│         │ MySQL  │           │ Redis  │          │RabbitMQ│                 │
│         │  8.0   │           │ Cache  │          │ (已有)  │                 │
│         └────────┘           └────────┘          └────────┘                 │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 2.2 核心组件说明

| 组件 | 位置 | 职责 |
|------|------|------|
| AuthProvider | 客户端 | 管理用户登录状态、Token刷新 |
| LicenseProvider | 客户端 | 管理授权状态、等级信息 |
| LicenseValidator | 客户端 | 本地+在线双重验证授权 |
| FeatureGuard | 客户端 | 根据等级控制功能访问 |
| DeviceService | 客户端 | 生成和管理设备指纹 |
| LicenseService | 后端 | 激活码生成、验证、绑定 |
| DeviceService | 后端 | 设备注册、淘汰、管理 |

---

## 3. 用户等级体系

### 3.1 等级定义

| 等级 | 标识 | 激活方式 | 设备数 | 有效期 | 顶栏显示 |
|------|------|----------|--------|--------|----------|
| **普通用户** | `FREE` | 无需激活 | 1 | 永久 | 灰色徽章 |
| **VIP** | `VIP` | 激活码 | 3 | 1年 | 金色徽章 |
| **SVIP** | `SVIP` | 升级激活码 | 5 | 1年 | 紫色徽章 |
| **管理员** | `ADMIN` | 特殊激活码 | 无限 | 永久 | 红色徽章 |

### 3.2 等级权限对比

```
功能特性                    FREE    VIP     SVIP    ADMIN
─────────────────────────────────────────────────────────
基础文件浏览                 ✓       ✓       ✓       ✓
视频播放                     ✓       ✓       ✓       ✓
音乐播放                     ✓       ✓       ✓       ✓
照片浏览                     ✓       ✓       ✓       ✓
连接源数量                   2       10      无限    无限
─────────────────────────────────────────────────────────
TMDB 刮削                    ✗       ✓       ✓       ✓
云同步                       ✗       基础    完整    完整
播放历史同步                 ✗       ✓       ✓       ✓
收藏同步                     ✗       ✓       ✓       ✓
─────────────────────────────────────────────────────────
PT 站点管理                  ✗       ✗       ✓       ✓
媒体管理工具                 ✗       ✗       ✓       ✓
高级下载器                   ✗       ✗       ✓       ✓
Trakt 集成                   ✗       ✗       ✓       ✓
─────────────────────────────────────────────────────────
管理后台访问                 ✗       ✗       ✗       ✓
用户管理                     ✗       ✗       ✗       ✓
激活码生成                   ✗       ✗       ✗       ✓
数据统计                     ✗       ✗       ✗       ✓
```

### 3.3 等级徽章设计

```dart
// 顶栏右侧用户等级徽章
┌────────────────────────────────────────────────────────┐
│  MyNAS                              [VIP ⭐] [头像]   │
└────────────────────────────────────────────────────────┘

// 徽章样式
FREE  : 灰色背景 + 用户图标
VIP   : 金色渐变背景 + 星星图标
SVIP  : 紫色渐变背景 + 皇冠图标
ADMIN : 红色背景 + 盾牌图标
```

---

## 4. 激活方式设计

### 4.1 双模式激活概览

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            激活方式选择                                      │
│                                                                             │
│    ┌─────────────────────────┐      ┌─────────────────────────┐            │
│    │      在线激活            │      │      离线激活            │            │
│    │    (账号登录)            │      │   (邮箱+激活码)          │            │
│    │                         │      │                         │            │
│    │  ┌───────────────────┐  │      │  ┌───────────────────┐  │            │
│    │  │ 用户名/邮箱 + 密码  │  │      │  │   邮箱地址         │  │            │
│    │  └───────────────────┘  │      │  └───────────────────┘  │            │
│    │           或            │      │  ┌───────────────────┐  │            │
│    │  ┌───────────────────┐  │      │  │   激活码           │  │            │
│    │  │   第三方登录       │  │      │  │ XXXX-XXXX-XXXX   │  │            │
│    │  │ Google/GitHub/微信 │  │      │  └───────────────────┘  │            │
│    │  └───────────────────┘  │      │                         │            │
│    │                         │      │                         │            │
│    │  特点:                  │      │  特点:                  │            │
│    │  • 实时验证             │      │  • 离线可用             │            │
│    │  • 多设备自动同步       │      │  • 定期在线验证         │            │
│    │  • 密码找回             │      │  • 邮箱绑定设备         │            │
│    │  • 实时权限更新         │      │  • 无需注册账号         │            │
│    └─────────────────────────┘      └─────────────────────────┘            │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 4.2 在线激活流程

#### 4.2.1 OAuth2 密码模式登录

```
┌──────────┐                                              ┌──────────┐
│  客户端   │                                              │   后端    │
└────┬─────┘                                              └────┬─────┘
     │                                                         │
     │  1. POST /oauth2/token                                  │
     │     grant_type=password                                 │
     │     username=xxx                                        │
     │     password=xxx                                        │
     │     client_id=mynas-app                                 │
     │     scope=openid profile license                        │
     │─────────────────────────────────────────────────────────>
     │                                                         │
     │                                                         │ 2. 验证凭证
     │                                                         │    查询用户
     │                                                         │    生成Token
     │                                                         │
     │  3. Response:                                           │
     │     {                                                   │
     │       "access_token": "eyJhbG...",                      │
     │       "refresh_token": "dGhpcy...",                     │
     │       "expires_in": 7200,                               │
     │       "token_type": "Bearer",                           │
     │       "scope": "openid profile license",                │
     │       "id_token": "eyJhbG..."                           │
     │     }                                                   │
     │<─────────────────────────────────────────────────────────
     │                                                         │
     │  4. GET /api/v1/user/license                            │
     │     Authorization: Bearer {access_token}                │
     │─────────────────────────────────────────────────────────>
     │                                                         │
     │                                                         │ 5. 查询用户授权
     │                                                         │    验证设备绑定
     │                                                         │    生成授权签名
     │                                                         │
     │  6. Response:                                           │
     │     {                                                   │
     │       "tier": "VIP",                                    │
     │       "expire_at": "2025-12-13",                        │
     │       "features": [...],                                │
     │       "devices": [...],                                 │
     │       "signature": "RSA签名"                            │
     │     }                                                   │
     │<─────────────────────────────────────────────────────────
     │                                                         │
     │  7. 本地存储授权信息                                      │
     │     更新 LicenseProvider                                 │
     │     应用功能权限                                          │
     │                                                         │
```

#### 4.2.2 第三方 OAuth2 登录

```
支持的第三方登录 (复用 allbs-admin 已有实现):
├── Google
├── GitHub
├── Gitee
├── 微信 (扫码/小程序)
└── QQ

流程: Authorization Code + PKCE
```

### 4.3 离线激活流程

#### 4.3.1 首次激活

```
┌──────────┐                                              ┌──────────┐
│  客户端   │                                              │   后端    │
└────┬─────┘                                              └────┬─────┘
     │                                                         │
     │  1. 用户输入:                                            │
     │     - 邮箱: user@example.com                            │
     │     - 激活码: ABCD-EFGH-IJKL-MNOP                       │
     │                                                         │
     │  2. POST /api/v1/license/activate                       │
     │     {                                                   │
     │       "email": "user@example.com",                      │
     │       "code": "ABCD-EFGH-IJKL-MNOP",                    │
     │       "device_fingerprint": "sha256...",                │
     │       "device_name": "iPhone 15 Pro",                   │
     │       "platform": "ios",                                │
     │       "app_version": "1.0.0"                            │
     │     }                                                   │
     │─────────────────────────────────────────────────────────>
     │                                                         │
     │                                                         │ 3. 验证激活码
     │                                                         │    检查邮箱绑定
     │                                                         │    检查设备数量
     │                                                         │    绑定设备
     │                                                         │    生成授权证书
     │                                                         │
     │  4. Response:                                           │
     │     {                                                   │
     │       "success": true,                                  │
     │       "license": {                                      │
     │         "tier": "VIP",                                  │
     │         "expire_at": "2025-12-13T00:00:00Z",            │
     │         "max_devices": 3,                               │
     │         "bound_devices": 1,                             │
     │         "offline_grace_days": 7,                        │
     │         "features": ["tmdb", "cloud_sync", ...]         │
     │       },                                                │
     │       "certificate": {                                  │
     │         "data": "base64编码的授权数据",                   │
     │         "signature": "RSA签名",                          │
     │         "issued_at": "2024-12-13T10:00:00Z",            │
     │         "valid_until": "2024-12-20T10:00:00Z"           │
     │       }                                                 │
     │     }                                                   │
     │<─────────────────────────────────────────────────────────
     │                                                         │
     │  5. 安全存储授权证书                                      │
     │     更新 LicenseProvider                                 │
     │     应用功能权限                                          │
     │                                                         │
```

#### 4.3.2 离线验证机制

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          离线验证流程                                        │
│                                                                             │
│  App 启动                                                                   │
│      │                                                                      │
│      ▼                                                                      │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ 1. 读取本地授权证书 (SecureStorage)                                   │   │
│  │    - certificate.data (授权数据)                                     │   │
│  │    - certificate.signature (RSA签名)                                 │   │
│  │    - certificate.valid_until (证书有效期)                            │   │
│  └───────────────────────────────┬─────────────────────────────────────┘   │
│                                  │                                          │
│                                  ▼                                          │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ 2. 本地验证 (无需网络)                                                │   │
│  │    a. 使用内置 RSA 公钥验证签名                                       │   │
│  │    b. 检查证书有效期 (valid_until)                                   │   │
│  │    c. 检查授权过期时间 (expire_at)                                   │   │
│  │    d. 验证设备指纹匹配                                                │   │
│  └───────────────────────────────┬─────────────────────────────────────┘   │
│                                  │                                          │
│              ┌───────────────────┼───────────────────┐                     │
│              │                   │                   │                     │
│              ▼                   ▼                   ▼                     │
│      ┌───────────────┐   ┌───────────────┐   ┌───────────────┐            │
│      │  验证通过     │   │  证书过期     │   │  授权过期     │            │
│      │  (正常使用)   │   │ (需在线刷新)  │   │  (功能降级)   │            │
│      └───────┬───────┘   └───────┬───────┘   └───────┬───────┘            │
│              │                   │                   │                     │
│              ▼                   ▼                   ▼                     │
│      ┌───────────────┐   ┌───────────────┐   ┌───────────────┐            │
│      │ 应用完整权限   │   │ 尝试在线刷新  │   │ 降级为FREE   │            │
│      │ 后台静默刷新   │   │  ↓成功→正常   │   │ 提示续费     │            │
│      │ (如有网络)    │   │  ↓失败→宽限期  │   │              │            │
│      └───────────────┘   └───────────────┘   └───────────────┘            │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ 3. 离线宽限期策略                                                     │   │
│  │    - 证书有效期: 7天 (每次在线验证后刷新)                              │   │
│  │    - 宽限期内: 完整功能可用，但会提示"请连接网络验证"                    │   │
│  │    - 宽限期后: 功能降级为FREE，直到在线验证成功                         │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 4.4 设备绑定与淘汰机制

#### 4.4.1 设备绑定规则

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          设备绑定规则                                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  设备上限 (按等级):                                                          │
│  ├── FREE  : 无限制                                                       │
│  ├── VIP   : 5 台设备                                                       │
│  ├── SVIP  : 10 台设备                                                       │
│  └── ADMIN : 3 台设备                                                         │
│                                                                             │
│  绑定触发时机:                                                               │
│  ├── 在线激活登录时                                                          │
│  ├── 离线激活成功时                                                          │
│  └── 每次启动App验证时                                                       │
│                                                                             │
│  设备标识生成 (多因素组合):                                                   │
│  ├── Android: androidId + fingerprint + hardware + device                  │
│  ├── iOS    : identifierForVendor + model + systemName                     │
│  ├── macOS  : hardwareUUID + model + serialNumber                          │
│  ├── Windows: machineGuid + processorId + biosSerial                       │
│  └── Linux  : machineId + cpuInfo + diskSerial                             │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

#### 4.4.2 FIFO 淘汰机制

```
场景: VIP用户 (上限3台) 已绑定3台设备，在第4台设备登录

当前绑定设备:
┌────────────────────────────────────────────────────────────┐
│  设备A (iPhone)      绑定时间: 2024-01-01  最后活跃: 2024-10-01  │
│  设备B (MacBook)     绑定时间: 2024-03-15  最后活跃: 2024-12-12  │
│  设备C (iPad)        绑定时间: 2024-06-20  最后活跃: 2024-12-10  │
└────────────────────────────────────────────────────────────┘

新设备D (Android) 请求绑定:
                    │
                    ▼
┌────────────────────────────────────────────────────────────┐
│  淘汰策略: 按绑定时间 FIFO (先进先出)                          │
│                                                            │
│  1. 找到最早绑定的设备: 设备A (2024-01-01)                    │
│  2. 将设备A标记为 is_active=false                           │
│  3. 绑定新设备D                                             │
│  4. 通知设备A被淘汰 (下次启动时提示)                          │
└────────────────────────────────────────────────────────────┘

淘汰后:
┌────────────────────────────────────────────────────────────┐
│  设备A (iPhone)      is_active: false  ← 已淘汰             │
│  设备B (MacBook)     is_active: true                       │
│  设备C (iPad)        is_active: true                       │
│  设备D (Android)     is_active: true   ← 新绑定             │
└────────────────────────────────────────────────────────────┘

被淘汰设备A的处理:
├── 下次启动时，本地验证失败 (设备指纹在服务端已失效)
├── 提示: "此设备已被其他设备替换，请重新激活"
└── 可选择: 重新激活 (会淘汰另一台旧设备) 或 使用其他激活码
```

---

## 5. 数据库设计

### 5.1 新增表结构

#### 5.1.1 激活码表 (nas_license)

```sql
-- 激活码/授权表
CREATE TABLE `nas_license` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '主键',
  `code` varchar(64) NOT NULL COMMENT '激活码 (加密存储)',
  `code_hash` varchar(64) NOT NULL COMMENT '激活码哈希 (用于快速查询)',
  `tier` varchar(20) NOT NULL DEFAULT 'VIP' COMMENT '等级: FREE/VIP/SVIP/ADMIN',
  `duration_days` int NOT NULL DEFAULT 365 COMMENT '有效期天数',
  `max_devices` int NOT NULL DEFAULT 3 COMMENT '最大设备数',

  -- 绑定信息
  `bind_email` varchar(200) DEFAULT NULL COMMENT '绑定邮箱',
  `bind_user_id` bigint DEFAULT NULL COMMENT '绑定用户ID (在线激活)',

  -- 状态信息
  `status` tinyint NOT NULL DEFAULT 0 COMMENT '状态: 0未使用 1已激活 2已过期 3已撤销',
  `activated_at` datetime DEFAULT NULL COMMENT '激活时间',
  `expire_at` datetime DEFAULT NULL COMMENT '过期时间',

  -- 使用统计
  `bound_device_count` int NOT NULL DEFAULT 0 COMMENT '已绑定设备数',

  -- 来源追踪
  `batch_no` varchar(64) DEFAULT NULL COMMENT '批次号',
  `channel` varchar(64) DEFAULT NULL COMMENT '渠道来源',
  `remark` varchar(500) DEFAULT NULL COMMENT '备注',

  -- 审计字段
  `created_by` bigint DEFAULT NULL COMMENT '创建人',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',

  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_code_hash` (`code_hash`),
  KEY `idx_bind_email` (`bind_email`),
  KEY `idx_bind_user_id` (`bind_user_id`),
  KEY `idx_status` (`status`),
  KEY `idx_expire_at` (`expire_at`),
  KEY `idx_batch_no` (`batch_no`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='激活码表';
```

#### 5.1.2 设备绑定表 (nas_device)

```sql
-- 设备绑定表
CREATE TABLE `nas_device` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '主键',
  `license_id` bigint NOT NULL COMMENT '激活码ID',
  `device_fingerprint` varchar(64) NOT NULL COMMENT '设备指纹',
  `device_name` varchar(100) DEFAULT NULL COMMENT '设备名称',
  `platform` varchar(20) NOT NULL COMMENT '平台: ios/android/macos/windows/linux',
  `app_version` varchar(20) DEFAULT NULL COMMENT 'App版本',
  `os_version` varchar(50) DEFAULT NULL COMMENT '系统版本',

  -- 状态信息
  `is_active` tinyint(1) NOT NULL DEFAULT 1 COMMENT '是否有效: 1有效 0已淘汰',
  `bound_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '绑定时间',
  `last_active_at` datetime DEFAULT NULL COMMENT '最后活跃时间',
  `last_ip` varchar(45) DEFAULT NULL COMMENT '最后IP地址',
  `last_location` varchar(100) DEFAULT NULL COMMENT '最后位置',

  -- 淘汰信息
  `deactivated_at` datetime DEFAULT NULL COMMENT '淘汰时间',
  `deactivated_by` varchar(64) DEFAULT NULL COMMENT '淘汰原因: fifo/manual/security',

  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_license_device` (`license_id`, `device_fingerprint`),
  KEY `idx_device_fingerprint` (`device_fingerprint`),
  KEY `idx_is_active` (`is_active`),
  KEY `idx_last_active_at` (`last_active_at`),
  CONSTRAINT `fk_device_license` FOREIGN KEY (`license_id`) REFERENCES `nas_license` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='设备绑定表';
```

#### 5.1.3 激活记录表 (nas_activation_log)

```sql
-- 激活记录表 (审计日志)
CREATE TABLE `nas_activation_log` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '主键',
  `license_id` bigint NOT NULL COMMENT '激活码ID',
  `device_id` bigint DEFAULT NULL COMMENT '设备ID',
  `action` varchar(32) NOT NULL COMMENT '操作: activate/verify/refresh/deactivate/expire',
  `result` varchar(20) NOT NULL COMMENT '结果: success/failed',
  `fail_reason` varchar(200) DEFAULT NULL COMMENT '失败原因',

  -- 请求信息
  `ip_address` varchar(45) DEFAULT NULL COMMENT 'IP地址',
  `user_agent` varchar(500) DEFAULT NULL COMMENT 'User-Agent',
  `device_fingerprint` varchar(64) DEFAULT NULL COMMENT '设备指纹',

  -- 审计字段
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',

  PRIMARY KEY (`id`),
  KEY `idx_license_id` (`license_id`),
  KEY `idx_action` (`action`),
  KEY `idx_created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='激活记录表';
```

### 5.2 扩展现有表

#### 5.2.1 扩展用户表 (sys_user)

```sql
-- 为 sys_user 表添加字段
ALTER TABLE `sys_user`
ADD COLUMN `nas_tier` varchar(20) DEFAULT 'FREE' COMMENT 'NAS等级: FREE/VIP/SVIP/ADMIN' AFTER `oauth2_enabled`,
ADD COLUMN `nas_expire_at` datetime DEFAULT NULL COMMENT 'NAS授权过期时间' AFTER `nas_tier`,
ADD COLUMN `nas_license_id` bigint DEFAULT NULL COMMENT '关联激活码ID' AFTER `nas_expire_at`,
ADD INDEX `idx_nas_tier` (`nas_tier`),
ADD INDEX `idx_nas_expire_at` (`nas_expire_at`);
```

### 5.3 ER 图

```
┌─────────────────┐       ┌─────────────────┐       ┌─────────────────┐
│    sys_user     │       │   nas_license   │       │   nas_device    │
├─────────────────┤       ├─────────────────┤       ├─────────────────┤
│ user_id (PK)    │       │ id (PK)         │       │ id (PK)         │
│ username        │       │ code            │       │ license_id (FK) │───┐
│ email           │  1:1  │ code_hash       │  1:N  │ device_finger   │   │
│ nas_tier        │◄─────►│ tier            │◄─────►│ device_name     │   │
│ nas_expire_at   │       │ duration_days   │       │ platform        │   │
│ nas_license_id  │───────│ max_devices     │       │ is_active       │   │
│ ...             │       │ bind_email      │       │ bound_at        │   │
└─────────────────┘       │ bind_user_id    │       │ last_active_at  │   │
                          │ status          │       │ ...             │   │
                          │ expire_at       │       └─────────────────┘   │
                          │ ...             │                             │
                          └─────────────────┘                             │
                                   │                                      │
                                   │ 1:N                                  │
                                   ▼                                      │
                          ┌─────────────────┐                             │
                          │nas_activation_log│                            │
                          ├─────────────────┤                             │
                          │ id (PK)         │                             │
                          │ license_id (FK) │─────────────────────────────┘
                          │ device_id (FK)  │
                          │ action          │
                          │ result          │
                          │ ...             │
                          └─────────────────┘
```

---

## 6. API 接口设计

### 6.1 接口概览

| 模块 | 接口 | 方法 | 描述 | 认证 |
|------|------|------|------|------|
| **激活** | `/api/v1/license/activate` | POST | 离线激活 | 无 |
| | `/api/v1/license/verify` | POST | 验证授权 | 无 |
| | `/api/v1/license/refresh` | POST | 刷新证书 | Token |
| **设备** | `/api/v1/device/list` | GET | 设备列表 | Token |
| | `/api/v1/device/unbind` | POST | 解绑设备 | Token |
| **用户** | `/api/v1/user/license` | GET | 获取授权信息 | Token |
| | `/api/v1/user/bind-license` | POST | 绑定激活码 | Token |
| **管理** | `/api/v1/admin/license/generate` | POST | 生成激活码 | Admin |
| | `/api/v1/admin/license/list` | GET | 激活码列表 | Admin |
| | `/api/v1/admin/license/revoke` | POST | 撤销激活码 | Admin |

### 6.2 核心接口详情

#### 6.2.1 离线激活

```yaml
POST /api/v1/license/activate

Request:
  Content-Type: application/json
  Body:
    email: string          # 邮箱地址
    code: string           # 激活码
    device_fingerprint: string  # 设备指纹
    device_name: string    # 设备名称
    platform: string       # 平台 (ios/android/macos/windows/linux)
    app_version: string    # App版本

Response (成功):
  HTTP 200
  {
    "code": 0,
    "msg": "success",
    "data": {
      "license": {
        "tier": "VIP",
        "expire_at": "2025-12-13T00:00:00Z",
        "max_devices": 3,
        "bound_devices": 1,
        "features": ["tmdb", "cloud_sync", "history_sync"]
      },
      "certificate": {
        "data": "eyJsaWNlbnNlX2lkIjo...",  # Base64编码
        "signature": "RSA_SHA256签名",
        "issued_at": "2024-12-13T10:00:00Z",
        "valid_until": "2024-12-20T10:00:00Z"  # 证书有效期7天
      },
      "device": {
        "id": 123,
        "name": "iPhone 15 Pro",
        "bound_at": "2024-12-13T10:00:00Z"
      }
    }
  }

Response (失败):
  HTTP 400
  {
    "code": 40001,
    "msg": "激活码无效或已过期",
    "data": null
  }

错误码:
  40001: 激活码无效
  40002: 激活码已过期
  40003: 激活码已被使用
  40004: 邮箱不匹配 (激活码已绑定其他邮箱)
  40005: 设备数量已达上限
```

#### 6.2.2 验证授权

```yaml
POST /api/v1/license/verify

Request:
  Content-Type: application/json
  Body:
    email: string              # 邮箱地址
    device_fingerprint: string # 设备指纹
    certificate_hash: string   # 本地证书哈希 (用于检查是否需要更新)

Response (成功):
  HTTP 200
  {
    "code": 0,
    "msg": "success",
    "data": {
      "valid": true,
      "tier": "VIP",
      "expire_at": "2025-12-13T00:00:00Z",
      "certificate_updated": true,  # 是否有新证书
      "certificate": {              # 仅当 certificate_updated=true 时返回
        "data": "...",
        "signature": "...",
        "issued_at": "...",
        "valid_until": "..."
      }
    }
  }

Response (设备已失效):
  HTTP 200
  {
    "code": 0,
    "msg": "success",
    "data": {
      "valid": false,
      "reason": "device_deactivated",
      "message": "此设备已被其他设备替换"
    }
  }
```

#### 6.2.3 获取用户授权信息 (在线激活)

```yaml
GET /api/v1/user/license

Headers:
  Authorization: Bearer {access_token}

Request:
  Query:
    device_fingerprint: string  # 当前设备指纹

Response:
  HTTP 200
  {
    "code": 0,
    "msg": "success",
    "data": {
      "user": {
        "id": 10001,
        "username": "john",
        "email": "john@example.com",
        "avatar": "https://..."
      },
      "license": {
        "id": 1,
        "tier": "SVIP",
        "expire_at": "2025-12-13T00:00:00Z",
        "max_devices": 5,
        "features": ["tmdb", "cloud_sync", "pt_sites", "media_management"]
      },
      "devices": [
        {
          "id": 1,
          "name": "iPhone 15 Pro",
          "platform": "ios",
          "is_current": true,
          "is_active": true,
          "last_active_at": "2024-12-13T10:00:00Z"
        },
        {
          "id": 2,
          "name": "MacBook Pro",
          "platform": "macos",
          "is_current": false,
          "is_active": true,
          "last_active_at": "2024-12-12T20:00:00Z"
        }
      ],
      "certificate": {
        "data": "...",
        "signature": "...",
        "issued_at": "...",
        "valid_until": "..."
      }
    }
  }
```

#### 6.2.4 生成激活码 (管理接口)

```yaml
POST /api/v1/admin/license/generate

Headers:
  Authorization: Bearer {admin_token}

Request:
  Content-Type: application/json
  Body:
    tier: string           # VIP/SVIP/ADMIN
    count: integer         # 生成数量 (1-100)
    duration_days: integer # 有效期天数
    max_devices: integer   # 最大设备数
    batch_no: string       # 批次号 (可选)
    channel: string        # 渠道来源 (可选)
    remark: string         # 备注 (可选)

Response:
  HTTP 200
  {
    "code": 0,
    "msg": "success",
    "data": {
      "batch_no": "BATCH-20241213-001",
      "count": 10,
      "codes": [
        "ABCD-EFGH-IJKL-MN01",
        "ABCD-EFGH-IJKL-MN02",
        ...
      ]
    }
  }
```

### 6.3 授权证书结构

```json
// certificate.data 解码后的结构
{
  "license_id": 12345,
  "tier": "VIP",
  "email": "user@example.com",
  "device_fingerprint": "sha256...",
  "features": ["tmdb", "cloud_sync", "history_sync"],
  "max_devices": 3,
  "expire_at": "2025-12-13T00:00:00Z",
  "issued_at": "2024-12-13T10:00:00Z",
  "valid_until": "2024-12-20T10:00:00Z",
  "issuer": "mynas-license-server",
  "version": 1
}

// 签名验证
signature = RSA_SHA256(
  privateKey,
  SHA256(certificate.data)
)

// 客户端验证
isValid = RSA_SHA256_Verify(
  publicKey,  // 内置在App中
  signature,
  SHA256(certificate.data)
)
```

---

## 7. 客户端改造方案

### 7.1 新增目录结构

```
lib/
├── features/
│   └── account/                      # 新增: 账号模块
│       ├── data/
│       │   ├── datasources/
│       │   │   ├── account_local_datasource.dart
│       │   │   └── account_remote_datasource.dart
│       │   ├── models/
│       │   │   ├── user_model.dart
│       │   │   ├── license_model.dart
│       │   │   ├── device_model.dart
│       │   │   └── certificate_model.dart
│       │   └── repositories/
│       │       └── account_repository_impl.dart
│       ├── domain/
│       │   ├── entities/
│       │   │   ├── user_entity.dart
│       │   │   ├── license_entity.dart
│       │   │   └── device_entity.dart
│       │   ├── repositories/
│       │   │   └── account_repository.dart
│       │   └── usecases/
│       │       ├── login_usecase.dart
│       │       ├── activate_usecase.dart
│       │       └── verify_license_usecase.dart
│       └── presentation/
│           ├── pages/
│           │   ├── login_page.dart           # 登录页
│           │   ├── register_page.dart        # 注册页
│           │   ├── activate_page.dart        # 离线激活页
│           │   ├── devices_page.dart         # 设备管理页
│           │   └── account_settings_page.dart # 账号设置页
│           ├── providers/
│           │   ├── auth_provider.dart        # 认证状态
│           │   └── license_provider.dart     # 授权状态
│           └── widgets/
│               ├── tier_badge.dart           # 等级徽章
│               ├── login_form.dart
│               └── activation_form.dart
│
├── core/
│   ├── license/                      # 新增: 授权核心
│   │   ├── license_validator.dart    # 本地+在线验证
│   │   ├── certificate_manager.dart  # 证书管理
│   │   ├── device_fingerprint.dart   # 设备指纹
│   │   └── feature_guard.dart        # 功能权限守卫
│   │
│   └── network/
│       └── interceptors/
│           └── auth_interceptor.dart # 新增: 认证拦截器
│
└── shared/
    └── widgets/
        └── upgrade_prompt.dart       # 新增: 升级提示组件
```

### 7.2 核心 Provider 设计

#### 7.2.1 AuthProvider (认证状态)

```dart
// lib/features/account/presentation/providers/auth_provider.dart

/// 认证状态
@freezed
class AuthState with _$AuthState {
  /// 未认证
  const factory AuthState.unauthenticated() = AuthUnauthenticated;

  /// 认证中
  const factory AuthState.authenticating() = AuthAuthenticating;

  /// 已认证 (在线模式)
  const factory AuthState.authenticated({
    required UserEntity user,
    required String accessToken,
    required String refreshToken,
    required DateTime tokenExpireAt,
  }) = AuthAuthenticated;

  /// 离线激活
  const factory AuthState.offlineActivated({
    required String email,
    required LicenseEntity license,
  }) = AuthOfflineActivated;

  /// 认证失败
  const factory AuthState.error(String message) = AuthError;
}

/// 认证状态管理
@riverpod
class AuthNotifier extends _$AuthNotifier {
  @override
  AuthState build() {
    _initializeAuth();
    return const AuthState.unauthenticated();
  }

  /// 初始化: 检查本地存储的认证信息
  Future<void> _initializeAuth() async {
    final savedAuth = await ref.read(authStorageProvider).getSavedAuth();
    if (savedAuth != null) {
      state = savedAuth;
      // 后台验证
      unawaited(_backgroundVerify());
    }
  }

  /// 在线登录
  Future<void> loginWithPassword(String username, String password) async {
    state = const AuthState.authenticating();
    try {
      final result = await ref.read(accountRepositoryProvider).login(
        username: username,
        password: password,
        deviceFingerprint: await ref.read(deviceFingerprintProvider),
      );
      state = AuthState.authenticated(
        user: result.user,
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
        tokenExpireAt: result.tokenExpireAt,
      );
      // 保存到本地
      await ref.read(authStorageProvider).saveAuth(state);
    } catch (e, st) {
      AppError.handle(e, st, 'loginWithPassword');
      state = AuthState.error(e.toString());
    }
  }

  /// 离线激活
  Future<void> activateOffline(String email, String code) async {
    state = const AuthState.authenticating();
    try {
      final result = await ref.read(accountRepositoryProvider).activateOffline(
        email: email,
        code: code,
        deviceFingerprint: await ref.read(deviceFingerprintProvider),
        deviceName: await ref.read(deviceNameProvider),
        platform: Platform.operatingSystem,
      );
      state = AuthState.offlineActivated(
        email: email,
        license: result.license,
      );
      // 保存证书到本地
      await ref.read(certificateManagerProvider).saveCertificate(result.certificate);
    } catch (e, st) {
      AppError.handle(e, st, 'activateOffline');
      state = AuthState.error(e.toString());
    }
  }

  /// 登出
  Future<void> logout() async {
    await ref.read(authStorageProvider).clearAuth();
    await ref.read(certificateManagerProvider).clearCertificate();
    state = const AuthState.unauthenticated();
  }
}
```

#### 7.2.2 LicenseProvider (授权状态)

```dart
// lib/features/account/presentation/providers/license_provider.dart

/// 用户等级
enum UserTier {
  free('FREE', '免费用户'),
  vip('VIP', 'VIP会员'),
  svip('SVIP', 'SVIP会员'),
  admin('ADMIN', '管理员');

  final String code;
  final String label;
  const UserTier(this.code, this.label);
}

/// 授权状态
@freezed
class LicenseState with _$LicenseState {
  const factory LicenseState({
    required UserTier tier,
    required DateTime? expireAt,
    required List<String> features,
    required int maxDevices,
    required int boundDevices,
    required bool isOfflineMode,
    required DateTime? certificateValidUntil,
  }) = _LicenseState;

  factory LicenseState.free() => const LicenseState(
    tier: UserTier.free,
    expireAt: null,
    features: [],
    maxDevices: 1,
    boundDevices: 1,
    isOfflineMode: false,
    certificateValidUntil: null,
  );
}

/// 授权状态管理
@riverpod
class LicenseNotifier extends _$LicenseNotifier {
  @override
  LicenseState build() {
    // 监听认证状态变化
    ref.listen(authProvider, (previous, next) {
      _onAuthStateChanged(next);
    });
    return LicenseState.free();
  }

  void _onAuthStateChanged(AuthState authState) {
    authState.when(
      unauthenticated: () => state = LicenseState.free(),
      authenticating: () {},
      authenticated: (user, _, __, ___) => _loadOnlineLicense(),
      offlineActivated: (email, license) => _applyLicense(license),
      error: (_) => state = LicenseState.free(),
    );
  }

  /// 加载在线授权
  Future<void> _loadOnlineLicense() async {
    try {
      final licenseInfo = await ref.read(accountRepositoryProvider).getLicenseInfo(
        deviceFingerprint: await ref.read(deviceFingerprintProvider),
      );
      _applyLicense(licenseInfo.license);
    } catch (e, st) {
      AppError.handle(e, st, 'loadOnlineLicense');
    }
  }

  /// 应用授权
  void _applyLicense(LicenseEntity license) {
    state = LicenseState(
      tier: UserTier.values.firstWhere(
        (t) => t.code == license.tier,
        orElse: () => UserTier.free,
      ),
      expireAt: license.expireAt,
      features: license.features,
      maxDevices: license.maxDevices,
      boundDevices: license.boundDevices,
      isOfflineMode: license.isOfflineMode,
      certificateValidUntil: license.certificateValidUntil,
    );
  }

  /// 检查功能是否可用
  bool hasFeature(String feature) {
    if (state.tier == UserTier.admin) return true;
    return state.features.contains(feature);
  }

  /// 检查是否过期
  bool get isExpired {
    if (state.tier == UserTier.free) return false;
    if (state.expireAt == null) return false;
    return DateTime.now().isAfter(state.expireAt!);
  }
}
```

### 7.3 功能权限守卫

```dart
// lib/core/license/feature_guard.dart

/// 功能标识
class Features {
  // 基础功能
  static const String fileBrowser = 'file_browser';
  static const String videoPlayer = 'video_player';
  static const String musicPlayer = 'music_player';
  static const String photoViewer = 'photo_viewer';

  // VIP 功能
  static const String tmdbScraping = 'tmdb';
  static const String cloudSync = 'cloud_sync';
  static const String historySync = 'history_sync';
  static const String favoritesSync = 'favorites_sync';
  static const String unlimitedSources = 'unlimited_sources';

  // SVIP 功能
  static const String ptSites = 'pt_sites';
  static const String mediaManagement = 'media_management';
  static const String advancedDownloader = 'advanced_downloader';
  static const String traktIntegration = 'trakt';

  // 管理员功能
  static const String adminPanel = 'admin_panel';
}

/// 功能守卫 Widget
class FeatureGuard extends ConsumerWidget {
  final String feature;
  final Widget child;
  final Widget? fallback;
  final VoidCallback? onBlocked;

  const FeatureGuard({
    super.key,
    required this.feature,
    required this.child,
    this.fallback,
    this.onBlocked,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final license = ref.watch(licenseProvider);
    final hasFeature = ref.read(licenseProvider.notifier).hasFeature(feature);

    if (hasFeature) {
      return child;
    }

    return fallback ?? FeatureLockedWidget(
      feature: feature,
      currentTier: license.tier,
      onUpgrade: () => context.push('/account/upgrade'),
    );
  }
}

/// 功能守卫 Hook (用于非Widget场景)
bool useFeatureGuard(WidgetRef ref, String feature) {
  final license = ref.watch(licenseProvider);
  return ref.read(licenseProvider.notifier).hasFeature(feature);
}

/// 功能锁定提示
class FeatureLockedWidget extends StatelessWidget {
  final String feature;
  final UserTier currentTier;
  final VoidCallback onUpgrade;

  const FeatureLockedWidget({
    super.key,
    required this.feature,
    required this.currentTier,
    required this.onUpgrade,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text('此功能需要升级会员'),
          SizedBox(height: 8),
          Text(
            '当前等级: ${currentTier.label}',
            style: TextStyle(color: Colors.grey),
          ),
          SizedBox(height: 16),
          ElevatedButton(
            onPressed: onUpgrade,
            child: Text('立即升级'),
          ),
        ],
      ),
    );
  }
}
```

### 7.4 设备指纹生成

```dart
// lib/core/license/device_fingerprint.dart

/// 设备指纹生成器
@riverpod
Future<String> deviceFingerprint(DeviceFingerprintRef ref) async {
  final deviceInfo = DeviceInfoPlugin();
  final factors = <String>[];

  if (Platform.isAndroid) {
    final info = await deviceInfo.androidInfo;
    factors.addAll([
      info.id,
      info.fingerprint,
      info.hardware,
      info.device,
      info.model,
      info.brand,
    ]);
  } else if (Platform.isIOS) {
    final info = await deviceInfo.iosInfo;
    factors.addAll([
      info.identifierForVendor ?? '',
      info.model,
      info.systemName,
      info.name,
    ]);
  } else if (Platform.isMacOS) {
    final info = await deviceInfo.macOsInfo;
    factors.addAll([
      info.systemGUID ?? '',
      info.model,
      info.computerName,
    ]);
  } else if (Platform.isWindows) {
    final info = await deviceInfo.windowsInfo;
    factors.addAll([
      info.deviceId,
      info.computerName,
      info.productId,
    ]);
  } else if (Platform.isLinux) {
    final info = await deviceInfo.linuxInfo;
    factors.addAll([
      info.machineId ?? '',
      info.name,
      info.id,
    ]);
  }

  // 过滤空值并生成哈希
  final raw = factors.where((f) => f.isNotEmpty).join('|');
  final bytes = utf8.encode(raw);
  final digest = sha256.convert(bytes);

  return digest.toString();
}

/// 设备名称
@riverpod
Future<String> deviceName(DeviceNameRef ref) async {
  final deviceInfo = DeviceInfoPlugin();

  if (Platform.isAndroid) {
    final info = await deviceInfo.androidInfo;
    return '${info.brand} ${info.model}';
  } else if (Platform.isIOS) {
    final info = await deviceInfo.iosInfo;
    return info.name;
  } else if (Platform.isMacOS) {
    final info = await deviceInfo.macOsInfo;
    return info.computerName;
  } else if (Platform.isWindows) {
    final info = await deviceInfo.windowsInfo;
    return info.computerName;
  } else if (Platform.isLinux) {
    final info = await deviceInfo.linuxInfo;
    return info.name;
  }

  return 'Unknown Device';
}
```

### 7.5 路由守卫

```dart
// lib/app/router/router.dart

// 添加认证重定向逻辑
GoRouter createRouter(Ref ref) {
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final authState = ref.read(authProvider);
      final isAuthRoute = state.matchedLocation.startsWith('/auth');

      // 未认证且不在认证页面 -> 跳转到启动页
      if (authState is AuthUnauthenticated && !isAuthRoute) {
        return '/startup';
      }

      // 已认证且在认证页面 -> 跳转到主页
      if ((authState is AuthAuthenticated || authState is AuthOfflineActivated)
          && isAuthRoute) {
        return '/video';
      }

      return null;
    },
    routes: [
      // 启动页 (选择登录方式)
      GoRoute(
        path: '/startup',
        builder: (_, __) => const StartupPage(),
      ),

      // 认证相关页面
      GoRoute(
        path: '/auth/login',
        builder: (_, __) => const LoginPage(),
      ),
      GoRoute(
        path: '/auth/register',
        builder: (_, __) => const RegisterPage(),
      ),
      GoRoute(
        path: '/auth/activate',
        builder: (_, __) => const ActivatePage(),
      ),

      // 主页面 (需要认证)
      ShellRoute(
        builder: (_, __, child) => MainScaffold(child: child),
        routes: [
          // ... 现有路由
        ],
      ),

      // 账号设置
      GoRoute(
        path: '/account/settings',
        builder: (_, __) => const AccountSettingsPage(),
      ),
      GoRoute(
        path: '/account/devices',
        builder: (_, __) => const DevicesPage(),
      ),
    ],
  );
}
```

### 7.6 顶栏用户徽章

```dart
// lib/shared/widgets/tier_badge.dart

class TierBadge extends ConsumerWidget {
  const TierBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final license = ref.watch(licenseProvider);
    final auth = ref.watch(authProvider);

    return GestureDetector(
      onTap: () => context.push('/account/settings'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          gradient: _getTierGradient(license.tier),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: _getTierColor(license.tier).withValues(alpha: 0.3),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _getTierIcon(license.tier),
              size: 14,
              color: Colors.white,
            ),
            const SizedBox(width: 4),
            Text(
              license.tier.label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  LinearGradient _getTierGradient(UserTier tier) {
    switch (tier) {
      case UserTier.free:
        return LinearGradient(colors: [Colors.grey.shade600, Colors.grey.shade800]);
      case UserTier.vip:
        return const LinearGradient(colors: [Color(0xFFFFD700), Color(0xFFFFA500)]);
      case UserTier.svip:
        return const LinearGradient(colors: [Color(0xFF9B59B6), Color(0xFF8E44AD)]);
      case UserTier.admin:
        return const LinearGradient(colors: [Color(0xFFE74C3C), Color(0xFFC0392B)]);
    }
  }

  Color _getTierColor(UserTier tier) {
    switch (tier) {
      case UserTier.free:
        return Colors.grey;
      case UserTier.vip:
        return const Color(0xFFFFD700);
      case UserTier.svip:
        return const Color(0xFF9B59B6);
      case UserTier.admin:
        return const Color(0xFFE74C3C);
    }
  }

  IconData _getTierIcon(UserTier tier) {
    switch (tier) {
      case UserTier.free:
        return Icons.person_outline;
      case UserTier.vip:
        return Icons.star;
      case UserTier.svip:
        return Icons.workspace_premium;
      case UserTier.admin:
        return Icons.shield;
    }
  }
}
```

---

## 8. 后端扩展方案

### 8.1 新增模块结构

```
allbs-admin/src/main/java/cn/allbs/admin/
├── controller/
│   └── nas/                          # 新增
│       ├── NasLicenseController.java     # 激活码管理
│       ├── NasDeviceController.java      # 设备管理
│       └── NasActivationController.java  # 激活接口
│
├── service/
│   └── nas/                          # 新增
│       ├── NasLicenseService.java
│       ├── NasLicenseServiceImpl.java
│       ├── NasDeviceService.java
│       ├── NasDeviceServiceImpl.java
│       └── NasCertificateService.java    # 证书签名服务
│
├── entity/
│   └── nas/                          # 新增
│       ├── NasLicenseEntity.java
│       ├── NasDeviceEntity.java
│       └── NasActivationLogEntity.java
│
├── mapper/
│   └── nas/                          # 新增
│       ├── NasLicenseMapper.java
│       ├── NasDeviceMapper.java
│       └── NasActivationLogMapper.java
│
├── dto/
│   └── nas/                          # 新增
│       ├── ActivateRequest.java
│       ├── ActivateResponse.java
│       ├── LicenseGenerateRequest.java
│       └── CertificateDTO.java
│
└── config/
    └── NasLicenseConfig.java         # 新增: 激活码配置
```

### 8.2 核心服务实现

#### 8.2.1 激活码服务

```java
// NasLicenseServiceImpl.java

@Service
@RequiredArgsConstructor
public class NasLicenseServiceImpl implements NasLicenseService {

    private final NasLicenseMapper licenseMapper;
    private final NasDeviceMapper deviceMapper;
    private final NasActivationLogMapper logMapper;
    private final NasCertificateService certificateService;
    private final SysUserService userService;

    @Override
    @Transactional
    public ActivateResponse activateOffline(ActivateRequest request) {
        // 1. 验证激活码
        String codeHash = DigestUtils.sha256Hex(request.getCode());
        NasLicenseEntity license = licenseMapper.selectOne(
            Wrappers.<NasLicenseEntity>lambdaQuery()
                .eq(NasLicenseEntity::getCodeHash, codeHash)
        );

        if (license == null) {
            throw new BusinessException("激活码无效");
        }

        if (license.getStatus() == LicenseStatus.EXPIRED) {
            throw new BusinessException("激活码已过期");
        }

        if (license.getStatus() == LicenseStatus.REVOKED) {
            throw new BusinessException("激活码已被撤销");
        }

        // 2. 检查邮箱绑定
        if (license.getBindEmail() != null
            && !license.getBindEmail().equals(request.getEmail())) {
            throw new BusinessException("激活码已绑定其他邮箱");
        }

        // 3. 检查设备数量
        long activeDeviceCount = deviceMapper.selectCount(
            Wrappers.<NasDeviceEntity>lambdaQuery()
                .eq(NasDeviceEntity::getLicenseId, license.getId())
                .eq(NasDeviceEntity::getIsActive, true)
        );

        if (activeDeviceCount >= license.getMaxDevices()) {
            // FIFO淘汰最早绑定的设备
            deactivateOldestDevice(license.getId());
        }

        // 4. 绑定设备
        NasDeviceEntity device = bindDevice(license.getId(), request);

        // 5. 更新激活码状态
        if (license.getStatus() == LicenseStatus.UNUSED) {
            license.setStatus(LicenseStatus.ACTIVE);
            license.setBindEmail(request.getEmail());
            license.setActivatedAt(LocalDateTime.now());
            license.setExpireAt(LocalDateTime.now().plusDays(license.getDurationDays()));
        }
        license.setBoundDeviceCount((int) activeDeviceCount + 1);
        licenseMapper.updateById(license);

        // 6. 生成授权证书
        CertificateDTO certificate = certificateService.generateCertificate(license, device);

        // 7. 记录日志
        saveActivationLog(license.getId(), device.getId(), "activate", "success", request);

        // 8. 返回结果
        return ActivateResponse.builder()
            .license(toLicenseDTO(license))
            .certificate(certificate)
            .device(toDeviceDTO(device))
            .build();
    }

    @Override
    public VerifyResponse verify(VerifyRequest request) {
        // 根据邮箱和设备指纹查找授权
        NasDeviceEntity device = deviceMapper.selectOne(
            Wrappers.<NasDeviceEntity>lambdaQuery()
                .eq(NasDeviceEntity::getDeviceFingerprint, request.getDeviceFingerprint())
                .eq(NasDeviceEntity::getIsActive, true)
        );

        if (device == null) {
            return VerifyResponse.invalid("device_not_found", "设备未绑定");
        }

        NasLicenseEntity license = licenseMapper.selectById(device.getLicenseId());

        if (!license.getBindEmail().equals(request.getEmail())) {
            return VerifyResponse.invalid("email_mismatch", "邮箱不匹配");
        }

        if (license.getStatus() != LicenseStatus.ACTIVE) {
            return VerifyResponse.invalid("license_inactive", "授权已失效");
        }

        if (license.getExpireAt().isBefore(LocalDateTime.now())) {
            return VerifyResponse.invalid("license_expired", "授权已过期");
        }

        // 更新最后活跃时间
        device.setLastActiveAt(LocalDateTime.now());
        device.setLastIp(request.getIpAddress());
        deviceMapper.updateById(device);

        // 检查是否需要更新证书
        CertificateDTO certificate = null;
        if (shouldRefreshCertificate(request.getCertificateHash(), license, device)) {
            certificate = certificateService.generateCertificate(license, device);
        }

        return VerifyResponse.valid(toLicenseDTO(license), certificate);
    }

    private void deactivateOldestDevice(Long licenseId) {
        NasDeviceEntity oldest = deviceMapper.selectOne(
            Wrappers.<NasDeviceEntity>lambdaQuery()
                .eq(NasDeviceEntity::getLicenseId, licenseId)
                .eq(NasDeviceEntity::getIsActive, true)
                .orderByAsc(NasDeviceEntity::getBoundAt)
                .last("LIMIT 1")
        );

        if (oldest != null) {
            oldest.setIsActive(false);
            oldest.setDeactivatedAt(LocalDateTime.now());
            oldest.setDeactivatedBy("fifo");
            deviceMapper.updateById(oldest);
        }
    }

    @Override
    public List<String> generateLicenses(LicenseGenerateRequest request) {
        List<String> codes = new ArrayList<>();

        for (int i = 0; i < request.getCount(); i++) {
            String code = generateUniqueCode();

            NasLicenseEntity license = NasLicenseEntity.builder()
                .code(encryptCode(code))
                .codeHash(DigestUtils.sha256Hex(code))
                .tier(request.getTier())
                .durationDays(request.getDurationDays())
                .maxDevices(request.getMaxDevices())
                .status(LicenseStatus.UNUSED)
                .batchNo(request.getBatchNo())
                .channel(request.getChannel())
                .remark(request.getRemark())
                .createdBy(SecurityUtils.getCurrentUserId())
                .build();

            licenseMapper.insert(license);
            codes.add(code);
        }

        return codes;
    }

    private String generateUniqueCode() {
        // 格式: XXXX-XXXX-XXXX-XXXX (16位,不含分隔符)
        String chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // 排除易混淆字符 I,O,0,1
        StringBuilder code = new StringBuilder();
        SecureRandom random = new SecureRandom();

        for (int i = 0; i < 16; i++) {
            if (i > 0 && i % 4 == 0) {
                code.append("-");
            }
            code.append(chars.charAt(random.nextInt(chars.length())));
        }

        return code.toString();
    }
}
```

#### 8.2.2 证书签名服务

```java
// NasCertificateService.java

@Service
@RequiredArgsConstructor
public class NasCertificateService {

    @Value("${nas.license.private-key-path}")
    private String privateKeyPath;

    @Value("${nas.license.certificate-validity-days:7}")
    private int certificateValidityDays;

    private PrivateKey privateKey;

    @PostConstruct
    public void init() throws Exception {
        // 加载RSA私钥
        String keyContent = Files.readString(Path.of(privateKeyPath));
        KeyFactory keyFactory = KeyFactory.getInstance("RSA");
        PKCS8EncodedKeySpec keySpec = new PKCS8EncodedKeySpec(
            Base64.getDecoder().decode(keyContent)
        );
        this.privateKey = keyFactory.generatePrivate(keySpec);
    }

    public CertificateDTO generateCertificate(
        NasLicenseEntity license,
        NasDeviceEntity device
    ) {
        LocalDateTime now = LocalDateTime.now();
        LocalDateTime validUntil = now.plusDays(certificateValidityDays);

        // 构建证书数据
        Map<String, Object> certData = Map.of(
            "license_id", license.getId(),
            "tier", license.getTier(),
            "email", license.getBindEmail(),
            "device_fingerprint", device.getDeviceFingerprint(),
            "features", getFeaturesByTier(license.getTier()),
            "max_devices", license.getMaxDevices(),
            "expire_at", license.getExpireAt().toString(),
            "issued_at", now.toString(),
            "valid_until", validUntil.toString(),
            "issuer", "mynas-license-server",
            "version", 1
        );

        // Base64编码
        String dataJson = JsonUtils.toJson(certData);
        String dataBase64 = Base64.getEncoder().encodeToString(dataJson.getBytes());

        // RSA签名
        String signature = sign(dataBase64);

        return CertificateDTO.builder()
            .data(dataBase64)
            .signature(signature)
            .issuedAt(now)
            .validUntil(validUntil)
            .build();
    }

    private String sign(String data) {
        try {
            Signature signature = Signature.getInstance("SHA256withRSA");
            signature.initSign(privateKey);
            signature.update(data.getBytes(StandardCharsets.UTF_8));
            byte[] signedBytes = signature.sign();
            return Base64.getEncoder().encodeToString(signedBytes);
        } catch (Exception e) {
            throw new RuntimeException("签名失败", e);
        }
    }

    private List<String> getFeaturesByTier(String tier) {
        return switch (tier) {
            case "VIP" -> List.of("tmdb", "cloud_sync", "history_sync", "favorites_sync", "unlimited_sources");
            case "SVIP" -> List.of("tmdb", "cloud_sync", "history_sync", "favorites_sync", "unlimited_sources",
                                   "pt_sites", "media_management", "advanced_downloader", "trakt");
            case "ADMIN" -> List.of("*"); // 所有功能
            default -> List.of(); // FREE
        };
    }
}
```

### 8.3 定时任务

```java
// NasLicenseScheduler.java

@Component
@RequiredArgsConstructor
@Slf4j
public class NasLicenseScheduler {

    private final NasLicenseMapper licenseMapper;
    private final NasDeviceMapper deviceMapper;

    /**
     * 每天凌晨检查过期激活码
     */
    @Scheduled(cron = "0 0 1 * * ?")
    public void checkExpiredLicenses() {
        log.info("开始检查过期激活码...");

        int count = licenseMapper.update(null,
            Wrappers.<NasLicenseEntity>lambdaUpdate()
                .set(NasLicenseEntity::getStatus, LicenseStatus.EXPIRED)
                .eq(NasLicenseEntity::getStatus, LicenseStatus.ACTIVE)
                .lt(NasLicenseEntity::getExpireAt, LocalDateTime.now())
        );

        log.info("已将 {} 个激活码标记为过期", count);
    }

    /**
     * 每天清理超过30天未活跃的已淘汰设备记录
     */
    @Scheduled(cron = "0 0 2 * * ?")
    public void cleanupInactiveDevices() {
        log.info("开始清理不活跃设备记录...");

        int count = deviceMapper.delete(
            Wrappers.<NasDeviceEntity>lambdaQuery()
                .eq(NasDeviceEntity::getIsActive, false)
                .lt(NasDeviceEntity::getDeactivatedAt, LocalDateTime.now().minusDays(30))
        );

        log.info("已清理 {} 条设备记录", count);
    }
}
```

---

## 9. 安全与防破解

### 9.1 多层防护体系

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          安全防护层级                                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Layer 1: 代码层                                                            │
│  ├── Flutter 代码混淆 (--obfuscate --split-debug-info)                      │
│  ├── 关键逻辑 Native 化 (Rust/C++ via FFI)                                  │
│  └── 字符串加密 (API地址、公钥等敏感字符串)                                   │
│                                                                             │
│  Layer 2: 通信层                                                            │
│  ├── HTTPS + SSL Pinning (证书锁定)                                         │
│  ├── 请求签名 (HMAC-SHA256)                                                 │
│  ├── 时间戳验证 (防重放攻击)                                                 │
│  └── 设备指纹绑定 (请求必须携带)                                             │
│                                                                             │
│  Layer 3: 授权层                                                            │
│  ├── RSA 签名证书 (离线验证)                                                │
│  ├── 证书有效期控制 (7天强制刷新)                                            │
│  ├── 服务端实时验证 (在线模式)                                               │
│  └── 双重验证 (本地签名 + 服务端确认)                                        │
│                                                                             │
│  Layer 4: 运行时层                                                          │
│  ├── Root/越狱检测                                                          │
│  ├── 调试器检测                                                             │
│  ├── 模拟器检测                                                             │
│  ├── Hook框架检测 (Frida, Xposed)                                          │
│  └── 完整性校验 (签名验证)                                                  │
│                                                                             │
│  Layer 5: 服务端层                                                          │
│  ├── 设备行为分析 (异常检测)                                                 │
│  ├── IP/地理位置异常告警                                                    │
│  ├── 设备频繁变更限制                                                       │
│  ├── 激活码使用频率限制                                                     │
│  └── 黑名单机制                                                             │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 9.2 具体实现方案

#### 9.2.1 代码混淆配置

```yaml
# Flutter 构建命令
flutter build apk --release --obfuscate --split-debug-info=build/symbols
flutter build ios --release --obfuscate --split-debug-info=build/symbols
flutter build macos --release --obfuscate --split-debug-info=build/symbols
```

#### 9.2.2 SSL Pinning

```dart
// lib/core/network/ssl_pinning.dart

class SslPinningHttpClient {
  static const List<String> _pinnedCertificates = [
    // 证书SHA256指纹
    'sha256/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
    'sha256/BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=',
  ];

  static HttpClient createPinnedClient() {
    final client = HttpClient();
    client.badCertificateCallback = (cert, host, port) {
      // 验证证书指纹
      final certHash = sha256.convert(cert.der).toString();
      return _pinnedCertificates.any((pin) => pin.contains(certHash));
    };
    return client;
  }
}
```

#### 9.2.3 请求签名

```dart
// lib/core/network/request_signer.dart

class RequestSigner {
  static const String _secretKey = 'YOUR_HMAC_SECRET'; // 实际应从安全存储获取

  static Map<String, String> sign(Map<String, dynamic> params) {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final nonce = _generateNonce();

    // 构建签名字符串
    final sortedParams = SplayTreeMap<String, dynamic>.from(params);
    sortedParams['timestamp'] = timestamp;
    sortedParams['nonce'] = nonce;

    final signString = sortedParams.entries
        .map((e) => '${e.key}=${e.value}')
        .join('&');

    // HMAC-SHA256 签名
    final hmac = Hmac(sha256, utf8.encode(_secretKey));
    final digest = hmac.convert(utf8.encode(signString));

    return {
      'X-Timestamp': timestamp,
      'X-Nonce': nonce,
      'X-Signature': digest.toString(),
    };
  }

  static String _generateNonce() {
    final random = Random.secure();
    final values = List<int>.generate(16, (_) => random.nextInt(256));
    return base64Encode(values);
  }
}
```

#### 9.2.4 运行时安全检测

```dart
// lib/core/security/security_checker.dart

class SecurityChecker {
  /// 检查运行环境安全性
  static Future<SecurityCheckResult> check() async {
    final issues = <String>[];

    // 1. Root/越狱检测
    if (await _isRooted()) {
      issues.add('device_rooted');
    }

    // 2. 调试器检测
    if (_isDebuggerAttached()) {
      issues.add('debugger_attached');
    }

    // 3. 模拟器检测
    if (await _isEmulator()) {
      issues.add('emulator_detected');
    }

    // 4. Hook框架检测
    if (await _isHookFrameworkPresent()) {
      issues.add('hook_framework_detected');
    }

    return SecurityCheckResult(
      isSecure: issues.isEmpty,
      issues: issues,
    );
  }

  static Future<bool> _isRooted() async {
    if (Platform.isAndroid) {
      // 检查常见root文件
      final rootPaths = [
        '/system/app/Superuser.apk',
        '/sbin/su',
        '/system/bin/su',
        '/system/xbin/su',
        '/data/local/xbin/su',
        '/data/local/bin/su',
        '/system/sd/xbin/su',
        '/system/bin/failsafe/su',
        '/data/local/su',
      ];

      for (final path in rootPaths) {
        if (await File(path).exists()) {
          return true;
        }
      }
    } else if (Platform.isIOS) {
      // 检查越狱文件
      final jailbreakPaths = [
        '/Applications/Cydia.app',
        '/Library/MobileSubstrate/MobileSubstrate.dylib',
        '/bin/bash',
        '/usr/sbin/sshd',
        '/etc/apt',
        '/private/var/lib/apt/',
      ];

      for (final path in jailbreakPaths) {
        if (await File(path).exists()) {
          return true;
        }
      }
    }

    return false;
  }

  static bool _isDebuggerAttached() {
    // Dart层检测
    bool inDebugMode = false;
    assert(() {
      inDebugMode = true;
      return true;
    }());
    return inDebugMode;
  }

  static Future<bool> _isEmulator() async {
    final deviceInfo = DeviceInfoPlugin();

    if (Platform.isAndroid) {
      final info = await deviceInfo.androidInfo;
      // 检查模拟器特征
      return info.isPhysicalDevice == false ||
             info.fingerprint.contains('generic') ||
             info.model.contains('Emulator') ||
             info.model.contains('Android SDK');
    } else if (Platform.isIOS) {
      final info = await deviceInfo.iosInfo;
      return info.isPhysicalDevice == false;
    }

    return false;
  }

  static Future<bool> _isHookFrameworkPresent() async {
    if (Platform.isAndroid) {
      // 检查Xposed
      final xposedPaths = [
        '/system/framework/XposedBridge.jar',
        '/system/bin/app_process.orig',
      ];

      for (final path in xposedPaths) {
        if (await File(path).exists()) {
          return true;
        }
      }
    }

    // 检查Frida (通过端口)
    try {
      final socket = await Socket.connect('127.0.0.1', 27042,
          timeout: const Duration(milliseconds: 100));
      await socket.close();
      return true; // Frida默认端口可连接
    } catch (_) {
      // 连接失败，可能没有Frida
    }

    return false;
  }
}
```

### 9.3 服务端防护

```java
// SecurityInterceptor.java

@Component
@RequiredArgsConstructor
public class SecurityInterceptor implements HandlerInterceptor {

    private final RedisTemplate<String, Object> redisTemplate;

    @Override
    public boolean preHandle(HttpServletRequest request,
                            HttpServletResponse response,
                            Object handler) throws Exception {

        // 1. 验证请求签名
        if (!verifySignature(request)) {
            response.setStatus(401);
            response.getWriter().write("{\"code\":401,\"msg\":\"签名验证失败\"}");
            return false;
        }

        // 2. 验证时间戳 (防重放)
        String timestamp = request.getHeader("X-Timestamp");
        if (timestamp != null) {
            long requestTime = Long.parseLong(timestamp);
            long currentTime = System.currentTimeMillis();
            if (Math.abs(currentTime - requestTime) > 300000) { // 5分钟
                response.setStatus(401);
                response.getWriter().write("{\"code\":401,\"msg\":\"请求已过期\"}");
                return false;
            }
        }

        // 3. 验证Nonce (防重放)
        String nonce = request.getHeader("X-Nonce");
        if (nonce != null) {
            String key = "nonce:" + nonce;
            if (Boolean.TRUE.equals(redisTemplate.hasKey(key))) {
                response.setStatus(401);
                response.getWriter().write("{\"code\":401,\"msg\":\"重复请求\"}");
                return false;
            }
            redisTemplate.opsForValue().set(key, "1", 10, TimeUnit.MINUTES);
        }

        // 4. 设备指纹验证
        String deviceFingerprint = request.getHeader("X-Device-Fingerprint");
        if (deviceFingerprint != null) {
            // 检查设备是否在黑名单
            if (isDeviceBlacklisted(deviceFingerprint)) {
                response.setStatus(403);
                response.getWriter().write("{\"code\":403,\"msg\":\"设备已被禁用\"}");
                return false;
            }
        }

        return true;
    }

    private boolean verifySignature(HttpServletRequest request) {
        // HMAC签名验证逻辑
        // ...
        return true;
    }

    private boolean isDeviceBlacklisted(String fingerprint) {
        return Boolean.TRUE.equals(
            redisTemplate.opsForSet().isMember("device:blacklist", fingerprint)
        );
    }
}
```

---

## 10. 功能权限矩阵

### 10.1 完整权限矩阵

| 功能模块 | 功能点 | FREE | VIP | SVIP | ADMIN | 功能标识 |
|---------|--------|:----:|:---:|:----:|:-----:|----------|
| **文件浏览** | 基础浏览 | ✓ | ✓ | ✓ | ✓ | `file_browser` |
| | 连接源数量 | 2 | 10 | ∞ | ∞ | `unlimited_sources` |
| **视频** | 播放 | ✓ | ✓ | ✓ | ✓ | `video_player` |
| | TMDB刮削 | ✗ | ✓ | ✓ | ✓ | `tmdb` |
| | 字幕搜索 | ✗ | ✓ | ✓ | ✓ | `subtitle_search` |
| **音乐** | 播放 | ✓ | ✓ | ✓ | ✓ | `music_player` |
| | 歌词搜索 | ✗ | ✓ | ✓ | ✓ | `lyrics_search` |
| **照片** | 浏览 | ✓ | ✓ | ✓ | ✓ | `photo_viewer` |
| | AI分类 | ✗ | ✗ | ✓ | ✓ | `photo_ai` |
| **云同步** | 播放历史 | ✗ | ✓ | ✓ | ✓ | `history_sync` |
| | 收藏同步 | ✗ | ✓ | ✓ | ✓ | `favorites_sync` |
| | 设置同步 | ✗ | ✗ | ✓ | ✓ | `settings_sync` |
| **PT站点** | 站点管理 | ✗ | ✗ | ✓ | ✓ | `pt_sites` |
| **媒体管理** | NASTool | ✗ | ✗ | ✓ | ✓ | `media_management` |
| | MoviePilot | ✗ | ✗ | ✓ | ✓ | `media_management` |
| **下载器** | 基础下载 | ✓ | ✓ | ✓ | ✓ | `basic_downloader` |
| | qBittorrent | ✗ | ✗ | ✓ | ✓ | `advanced_downloader` |
| | Transmission | ✗ | ✗ | ✓ | ✓ | `advanced_downloader` |
| | Aria2 | ✗ | ✗ | ✓ | ✓ | `advanced_downloader` |
| **追踪** | Trakt集成 | ✗ | ✗ | ✓ | ✓ | `trakt` |
| **管理** | 管理后台 | ✗ | ✗ | ✗ | ✓ | `admin_panel` |

### 10.2 功能标识定义

```dart
// lib/core/license/features.dart

abstract class Features {
  // 基础功能 (FREE可用)
  static const fileBrowser = 'file_browser';
  static const videoPlayer = 'video_player';
  static const musicPlayer = 'music_player';
  static const photoViewer = 'photo_viewer';
  static const basicDownloader = 'basic_downloader';

  // VIP功能
  static const tmdb = 'tmdb';
  static const subtitleSearch = 'subtitle_search';
  static const lyricsSearch = 'lyrics_search';
  static const cloudSync = 'cloud_sync';
  static const historySync = 'history_sync';
  static const favoritesSync = 'favorites_sync';
  static const unlimitedSources = 'unlimited_sources';

  // SVIP功能
  static const photoAi = 'photo_ai';
  static const settingsSync = 'settings_sync';
  static const ptSites = 'pt_sites';
  static const mediaManagement = 'media_management';
  static const advancedDownloader = 'advanced_downloader';
  static const trakt = 'trakt';

  // ADMIN功能
  static const adminPanel = 'admin_panel';
  static const userManagement = 'user_management';
  static const licenseManagement = 'license_management';
  static const all = '*';

  /// 各等级包含的功能
  static const Map<String, List<String>> tierFeatures = {
    'FREE': [
      fileBrowser,
      videoPlayer,
      musicPlayer,
      photoViewer,
      basicDownloader,
    ],
    'VIP': [
      fileBrowser,
      videoPlayer,
      musicPlayer,
      photoViewer,
      basicDownloader,
      tmdb,
      subtitleSearch,
      lyricsSearch,
      cloudSync,
      historySync,
      favoritesSync,
      unlimitedSources,
    ],
    'SVIP': [
      fileBrowser,
      videoPlayer,
      musicPlayer,
      photoViewer,
      basicDownloader,
      tmdb,
      subtitleSearch,
      lyricsSearch,
      cloudSync,
      historySync,
      favoritesSync,
      unlimitedSources,
      photoAi,
      settingsSync,
      ptSites,
      mediaManagement,
      advancedDownloader,
      trakt,
    ],
    'ADMIN': [all],
  };
}
```

---

## 11. 实施计划

### 11.1 阶段划分

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            实施路线图                                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Phase 1: 基础架构 (Week 1-2)                                               │
│  ├── 数据库表创建和迁移                                                      │
│  ├── 后端激活码服务实现                                                      │
│  ├── RSA密钥生成和管理                                                      │
│  └── 基础API接口实现                                                        │
│                                                                             │
│  Phase 2: 客户端认证 (Week 3-4)                                             │
│  ├── 登录/注册/激活页面                                                      │
│  ├── AuthProvider/LicenseProvider 实现                                     │
│  ├── 设备指纹生成                                                           │
│  ├── 证书管理器实现                                                          │
│  └── 路由守卫集成                                                           │
│                                                                             │
│  Phase 3: 功能权限 (Week 5-6)                                               │
│  ├── FeatureGuard 组件实现                                                  │
│  ├── 各功能模块权限集成                                                      │
│  ├── 用户等级徽章                                                           │
│  └── 升级提示组件                                                           │
│                                                                             │
│  Phase 4: 安全加固 (Week 7-8)                                               │
│  ├── SSL Pinning                                                           │
│  ├── 请求签名                                                               │
│  ├── 代码混淆配置                                                           │
│  ├── 运行时安全检测                                                          │
│  └── 服务端安全拦截器                                                        │
│                                                                             │
│  Phase 5: 管理后台 (Week 9-10)                                              │
│  ├── 激活码管理页面                                                          │
│  ├── 用户管理页面                                                           │
│  ├── 设备管理页面                                                           │
│  └── 数据统计仪表盘                                                          │
│                                                                             │
│  Phase 6: 测试优化 (Week 11-12)                                             │
│  ├── 单元测试                                                               │
│  ├── 集成测试                                                               │
│  ├── 安全测试                                                               │
│  ├── 性能优化                                                               │
│  └── 文档完善                                                               │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 11.2 任务清单

#### Phase 1: 基础架构

- [ ] 创建 `nas_license` 表
- [ ] 创建 `nas_device` 表
- [ ] 创建 `nas_activation_log` 表
- [ ] 扩展 `sys_user` 表
- [ ] 生成 RSA 密钥对
- [ ] 实现 `NasLicenseService`
- [ ] 实现 `NasDeviceService`
- [ ] 实现 `NasCertificateService`
- [ ] 实现激活码生成接口
- [ ] 实现离线激活接口
- [ ] 实现授权验证接口
- [ ] 实现设备管理接口

#### Phase 2: 客户端认证

- [ ] 创建 `features/account` 模块结构
- [ ] 实现 `UserEntity` / `LicenseEntity` / `DeviceEntity`
- [ ] 实现 `AccountRepository`
- [ ] 实现 `AuthProvider`
- [ ] 实现 `LicenseProvider`
- [ ] 实现 `DeviceFingerprint` 生成器
- [ ] 实现 `CertificateManager`
- [ ] 实现 `LicenseValidator`
- [ ] 创建登录页面
- [ ] 创建注册页面
- [ ] 创建离线激活页面
- [ ] 创建设备管理页面
- [ ] 集成路由守卫

#### Phase 3: 功能权限

- [ ] 定义功能标识常量
- [ ] 实现 `FeatureGuard` Widget
- [ ] 实现 `useFeatureGuard` Hook
- [ ] 实现 `FeatureLockedWidget`
- [ ] 实现 `TierBadge` 组件
- [ ] 实现 `UpgradePrompt` 组件
- [ ] 集成视频模块权限
- [ ] 集成音乐模块权限
- [ ] 集成照片模块权限
- [ ] 集成PT站点模块权限
- [ ] 集成下载器模块权限
- [ ] 集成连接源数量限制

#### Phase 4: 安全加固

- [ ] 配置 Flutter 代码混淆
- [ ] 实现 SSL Pinning
- [ ] 实现请求签名
- [ ] 实现时间戳验证
- [ ] 实现 Nonce 防重放
- [ ] 实现 Root/越狱检测
- [ ] 实现调试器检测
- [ ] 实现模拟器检测
- [ ] 实现 Hook 框架检测
- [ ] 实现服务端安全拦截器
- [ ] 实现设备黑名单机制
- [ ] 实现异常行为告警

#### Phase 5: 管理后台

- [ ] 创建激活码列表页面
- [ ] 创建激活码生成页面
- [ ] 创建激活码详情页面
- [ ] 创建用户列表页面
- [ ] 创建用户详情页面
- [ ] 创建设备列表页面
- [ ] 创建统计仪表盘
- [ ] 实现批量操作功能
- [ ] 实现数据导出功能

#### Phase 6: 测试优化

- [ ] 编写单元测试 (服务层)
- [ ] 编写单元测试 (Provider)
- [ ] 编写集成测试 (API)
- [ ] 编写 Widget 测试
- [ ] 安全渗透测试
- [ ] 性能压力测试
- [ ] 修复发现的问题
- [ ] 编写用户文档
- [ ] 编写 API 文档

---

## 附录

### A. 激活码格式规范

```
格式: XXXX-XXXX-XXXX-XXXX
字符集: A-Z (排除 I, O) + 2-9 (排除 0, 1)
总字符: 32个可用字符
长度: 16位 (不含分隔符)
组合数: 32^16 ≈ 1.2 × 10^24

示例:
  VIP 激活码:  V7KP-M3NQ-X9RW-2TFC
  SVIP 激活码: S8LH-J4YB-K6ZD-5WGA
  ADMIN 激活码: AXYZ-1234-ABCD-5678
```

### B. RSA 密钥管理

```bash
# 生成2048位RSA密钥对
openssl genrsa -out private_key.pem 2048

# 导出公钥
openssl rsa -in private_key.pem -pubout -out public_key.pem

# 转换为PKCS8格式 (Java兼容)
openssl pkcs8 -topk8 -inform PEM -outform PEM -nocrypt \
  -in private_key.pem -out private_key_pkcs8.pem

# 密钥存储位置
后端: /config/keys/private_key_pkcs8.pem (仅服务器可访问)
客户端: 编译到应用中 (public_key.pem)
```

### C. 错误码定义

| 错误码 | 描述 | 处理方式 |
|--------|------|----------|
| 40001 | 激活码无效 | 提示用户检查激活码 |
| 40002 | 激活码已过期 | 提示续费或联系客服 |
| 40003 | 激活码已被使用 | 提示使用新激活码 |
| 40004 | 邮箱不匹配 | 提示使用绑定邮箱 |
| 40005 | 设备数量超限 | 提示管理设备或升级 |
| 40006 | 设备已被淘汰 | 提示重新激活 |
| 40007 | 证书验证失败 | 尝试在线刷新 |
| 40008 | 授权已过期 | 功能降级+提示续费 |
| 40009 | 请求签名无效 | 检查网络/重试 |
| 40010 | 设备已被禁用 | 联系客服 |

### D. 配置参数

```yaml
# application.yml
nas:
  license:
    # RSA私钥路径
    private-key-path: /config/keys/private_key_pkcs8.pem

    # 证书有效期 (天)
    certificate-validity-days: 7

    # 离线宽限期 (天)
    offline-grace-days: 7

    # 默认设备上限
    default-max-devices:
      VIP: 3
      SVIP: 5
      ADMIN: 999

    # 默认有效期 (天)
    default-duration-days:
      VIP: 365
      SVIP: 365
      ADMIN: 36500

    # 安全配置
    security:
      # 请求时间戳有效期 (秒)
      timestamp-validity: 300
      # Nonce缓存时间 (分钟)
      nonce-cache-minutes: 10
      # HMAC密钥 (生产环境应使用环境变量)
      hmac-secret: ${NAS_HMAC_SECRET}
```

---

## 更新记录

| 版本 | 日期 | 描述 |
|------|------|------|
| 1.0.0 | 2024-12-13 | 初始版本 |

---

> 文档结束
