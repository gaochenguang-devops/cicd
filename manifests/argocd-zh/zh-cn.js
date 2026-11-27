/**
 * ArgoCD UI 中文词库（翻译层）
 * nginx 在 argocd-server 返回的 index.html 中注入执行。
 * 只替换与词库精确匹配的可见文本，不动机器名/应用名/YAML 等业务数据。
 * 关闭：localStorage.setItem('argocd-zh','off') 后刷新。
 */
(function () {
  'use strict';
  if (window.__argoZhCnLoaded) return;
  window.__argoZhCnLoaded = true;

  var DICT = {
    "Username": "用户名",
    "Password": "密码",
    "Sign In": "登录",
    "Sign in": "登录",
    "LOG IN": "登录",
    "Log In": "登录",
    "Log in": "登录",
    "Login": "登录",
    "Log Out": "退出登录",
    "Log out": "退出登录",
    "User Info": "用户信息",
    "Applications": "应用",
    "Applications List": "应用列表",
    "Application": "应用",
    "Projects": "项目",
    "Project": "项目",
    "Repositories": "仓库",
    "Repository": "仓库",
    "Clusters": "集群",
    "Cluster": "集群",
    "Settings": "设置",
    "Docs": "文档",
    "Help": "帮助",
    "About": "关于",
    "Account": "账户",
    "Certificates": "证书",
    "Managed Resources": "纳管资源",
    "Search": "搜索",
    "Filters": "筛选",
    "Filter": "筛选",
    "APP NAME": "应用名称",
    "PROJECT": "项目",
    "NAMESPACE": "命名空间",
    "CLUSTER": "集群",
    "STATUS": "状态",
    "HEALTH": "健康状态",
    "SYNC STATUS": "同步状态",
    "LAST SYNC": "最后同步",
    "OPERATION": "操作",
    "Refresh": "刷新",
    "Refresh App": "刷新应用",
    "Hard Refresh": "强制刷新",
    "HARD REFRESH": "强制刷新",
    "Card View": "卡片视图",
    "List View": "列表视图",
    "Tile View": "磁贴视图",
    "NEW APP": "新建应用",
    "CREATE APPLICATION": "创建应用",
    "New Application": "新建应用",
    "Create Application": "创建应用",
    "Delete Application": "删除应用",
    "No applications": "暂无应用",
    "No results found": "未找到结果",
    "Loading": "加载中",
    "Loading...": "加载中...",
    "SUMMARY": "概览",
    "Summary": "概览",
    "PARAMETERS": "参数",
    "Parameters": "参数",
    "MANIFEST": "清单",
    "Manifest": "清单",
    "EVENTS": "事件",
    "Events": "事件",
    "DIFF": "差异",
    "Diff": "差异",
    "APP DIFF": "应用差异",
    "HISTORY AND ROLLBACK": "历史与回滚",
    "History and Rollback": "历史与回滚",
    "APP DETAILS": "应用详情",
    "App Details": "应用详情",
    "APPLICATION CONDITIONS": "应用状态条件",
    "DEPLOY": "部署",
    "Deploy": "部署",
    "INVENTORY": "资源清单",
    "Inventory": "资源清单",
    "LOGS": "日志",
    "Logs": "日志",
    "TERMINAL": "终端",
    "RESOURCE": "资源",
    "Resources": "资源",
    "NAME": "名称",
    "KIND": "类型",
    "VERSION": "版本",
    "GROUP": "组",
    "MESSAGE": "消息",
    "TIME": "时间",
    "REVISION": "版本号",
    "IMAGES": "镜像",
    "Sync": "同步",
    "SYNCHRONIZE": "同步",
    "Synchronize": "同步",
    "SYNC OPTIONS": "同步选项",
    "Sync Options": "同步选项",
    "Sync Policy": "同步策略",
    "PRUNE RESOURCES": "清理多余资源",
    "Prune Resources": "清理多余资源",
    "REPLACE": "替换",
    "DRY RUN": "试运行",
    "Dry Run": "试运行",
    "APPLY ONLY OUT OF SYNC": "仅应用不同步的资源",
    "ROLLBACK": "回滚",
    "Rollback": "回滚",
    "Enable Auto-Sync": "启用自动同步",
    "Disable Auto-Sync": "禁用自动同步",
    "Auto-Sync": "自动同步",
    "Cancel": "取消",
    "CANCEL": "取消",
    "Close": "关闭",
    "CLOSE": "关闭",
    "Submit": "提交",
    "Save": "保存",
    "Edit": "编辑",
    "Delete": "删除",
    "Create": "创建",
    "Are you sure?": "确认执行？",
    "Confirm": "确认",
    "Synced": "已同步",
    "OutOfSync": "不同步",
    "Unknown": "未知",
    "Healthy": "健康",
    "Unhealthy": "不健康",
    "Degraded": "降级",
    "Progressing": "进行中",
    "Missing": "缺失",
    "Suspended": "已暂停",
    "Terminating": "终止中",
    "Failed": "失败",
    "Succeeded": "成功",
    "Running": "运行中",
    "Pending": "等待中",
    "SUCCESSFUL": "成功",
    "FAILED": "失败",
    "Connection Status": "连接状态",
    "Connection Successful": "连接成功",
    "Connection Failed": "连接失败",
    "Application Name": "应用名称",
    "Source": "来源",
    "Destination": "目标",
    "Repository URL": "仓库地址",
    "Path": "路径",
    "Server": "服务器",
    "Cluster URL": "集群地址",
    "Required field": "必填项",
    "Error": "错误",
    "Warning": "警告",
    "Role": "角色",
    "Token": "令牌",
    "Generate New Token": "生成新令牌",
    "Description": "描述",
    "URL": "地址",
    "Enable SSL verification": "启用 SSL 校验",
    "Connect": "连接",
    "Add": "添加",
    "Update": "更新",
    "Test": "测试",
    "Copy": "复制",
    "Copied": "已复制",
    "View Details": "查看详情",
    "Back": "返回",
    "Next": "下一步",
    "Previous": "上一步",
    "Finish": "完成",
    "Health": "健康状态",
    "Status": "状态",
    "Automatic": "自动",
    "Manual": "手动",
    "Prune": "清理",
    "Self Heal": "自愈",
    "SelfHeal": "自愈",

    /* ---------- 二轮补充 ---------- */
    "Documentation": "文档",
    "ApplicationSets": "应用集",
    "ApplicationSet": "应用集",
    "Syncing": "同步中",
    "Tiles": "磁贴",
    "List": "列表",
    "Open application": "打开应用",
    "Add Favorite": "收藏",
    "Remove Favorite": "取消收藏",
    "Sort": "排序",
    "Sort by": "排序方式",
    "Items per page": "每页条数",
    "Search applications...": "搜索应用...",
    "No favorites": "暂无收藏",
    "App Sync Status": "应用同步状态",
    "Sync Status": "同步状态",
    "App Health": "应用健康",
    "Auto-Sync": "自动同步",
    "Manual Sync": "手动同步",
    "Refresh Now": "立即刷新",
    "Show More": "显示更多",
    "Show Less": "收起",
    "Conditions": "状态条件",
    "Parameters": "参数",
    "Source Repos": "源仓库",
    "Destinations": "目标",
    "Permitted destinations": "允许的目标",
    "Sync Windows": "同步窗口",
    "Token Expires": "令牌过期",
    "Submit changes": "提交变更",
    "Go to start page": "返回首页",
    "App Details": "应用详情",
    "Sync Result": "同步结果",
    "Application resources": "应用资源",
    "Out of sync": "不同步",
    "Last Sync Result": "最近同步结果",
    "Operation": "操作",
    "Started At": "开始时间",
    "Finished At": "结束时间",
    "Duration": "耗时",
    "Initiated By": "发起人",
    "Favorites Only": "仅收藏",
    "HEALTH STATUS": "健康状态",
    "OPERATION STATUS": "操作状态",
    "Target Revision": "目标版本",
    "Labels": "标签",
    "Created At": "创建时间",
    "Last Sync": "最后同步",
    "Revision History": "版本历史",
    "Rollback to": "回滚到",
    "PROJECTS": "项目",
    "Example Projects": "示例项目",
    "Auto sync is enabled": "已启用自动同步",
    "Auto sync is enabled.": "已启用自动同步。",
    "Auto sync is disabled": "自动同步已禁用",
    "Sync OK": "同步成功",
    "Sync Failed": "同步失败",
    "Resource filters": "资源筛选",
    "KINDS": "类型",
    "NAMES": "名称",
    "Author": "作者",
    "Comment": "注释",
    "Health Status": "健康状态",
    "Operation Status": "操作状态"
  };

  var SKIP_TAGS = {
    SCRIPT: 1, STYLE: 1, PRE: 1, CODE: 1, TEXTAREA: 1, KBD: 1,
    NOSCRIPT: 1, IFRAME: 1, SVG: 1, CANVAS: 1
  };
  var ATTRS = ['title', 'placeholder', 'aria-label'];

  // 大小写不敏感索引
  var UP_DICT = {}, CAP_DICT = {};
  (function () {
    for (var k in DICT) {
      if (!Object.prototype.hasOwnProperty.call(DICT, k)) continue;
      UP_DICT[k.toUpperCase()] = DICT[k];
      CAP_DICT[k.charAt(0).toUpperCase() + k.slice(1).toLowerCase()] = DICT[k];
    }
  })();

  // 带变量的文本：只替换前缀（按长度从长到短匹配）
  var PREFIXES = [
    ['Search applications', '搜索应用'],
    ['Items per page:', '每页条数：'],
    ['Sort:', '排序：'],
    ['Sync Status:', '同步状态：'],
    ['Applications ', '应用 '],
    ['Application ', '应用 '],
    ['Projects ', '项目 '],
    ['Settings ', '设置 '],
    ['Documentation ', '文档 ']
  ];

  try {
    if (window.localStorage && window.localStorage.getItem('argocd-zh') === 'off') return;
  } catch (e) { /* 忽略 */ }

  function lookup(word) {
    if (Object.prototype.hasOwnProperty.call(DICT, word)) return DICT[word];
    var up = word.toUpperCase();
    if (word === up && Object.prototype.hasOwnProperty.call(UP_DICT, up)) return UP_DICT[up];
    var cap = word.charAt(0).toUpperCase() + word.slice(1).toLowerCase();
    if (Object.prototype.hasOwnProperty.call(CAP_DICT, cap)) return CAP_DICT[cap];
    return null;
  }

  function translate(text) {
    if (!text) return text;
    var raw = text.trim();
    if (raw.length < 2 || raw.length > 80) return text;
    if (!/[A-Za-z]/.test(raw)) return text;

    // 1) 相对时间
    var rel = raw.match(/^(\d+)\s+(second|minute|hour|day)s?\s+ago$/i);
    if (rel) {
      var unit = { second: '秒', minute: '分钟', hour: '小时', day: '天' }[rel[2].toLowerCase()];
      return text.replace(raw, rel[1] + ' ' + unit + '前');
    }

    // 2) 去掉结尾冒号后查词库（"Project:" -> "项目："）
    var core = raw, tail = '';
    if (core.slice(-1) === ':') { core = core.slice(0, -1).trim(); tail = '：'; }

    var hit = lookup(core);
    if (hit) return text.replace(raw, hit + tail);

    // 3) 前缀规则（处理 "Sort: 名称"、"Application Filters" 这类带变量的文本）
    for (var i = 0; i < PREFIXES.length; i++) {
      var key = PREFIXES[i][0];
      if (raw.indexOf(key) === 0 && raw.length > key.length) {
        var rest = raw.slice(key.length);
        var restHit = lookup(rest.trim());
        return text.replace(raw, PREFIXES[i][1] + (restHit || rest));
      }
    }
    return text;
  }

  function translateAttrs(el) {
    for (var i = 0; i < ATTRS.length; i++) {
      var a = ATTRS[i];
      var v = el.getAttribute && el.getAttribute(a);
      if (!v) continue;
      var nv = translate(v);
      if (nv !== v) el.setAttribute(a, nv);
    }
  }

  function walk(node) {
    if (!node) return;
    if (node.nodeType === 3) {
      var p = node.parentNode;
      if (p && p.nodeName && !SKIP_TAGS[p.nodeName]) {
        var nv = translate(node.nodeValue);
        if (nv !== node.nodeValue) node.nodeValue = nv;
      }
      return;
    }
    if (node.nodeType !== 1) return;
    if (SKIP_TAGS[node.nodeName]) return;
    translateAttrs(node);
    for (var i = 0, kids = node.childNodes; i < kids.length; i++) walk(kids[i]);
  }

  function observe() {
    var mo = new MutationObserver(function (muts) {
      for (var i = 0; i < muts.length; i++) {
        var m = muts[i];
        if (m.type === 'childList') {
          for (var j = 0; j < m.addedNodes.length; j++) walk(m.addedNodes[j]);
        } else if (m.type === 'characterData') {
          var old = m.target.nodeValue;
          var nv = translate(old);
          if (nv !== old) m.target.nodeValue = nv;
        }
      }
    });
    mo.observe(document.documentElement, {
      childList: true, subtree: true, characterData: true
    });
  }

  function start() {
    walk(document.body);
    observe();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', start);
  } else {
    start();
  }
})();
