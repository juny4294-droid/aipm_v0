/**
 * 公式のセキュリティ告知を読み、一覧のバージョンに当たった件数だけを表示する。
 * 確認は preview、既読にするのは seed、新しい告知だけ出すのは post。
 */

var USER_AGENT = 'security-advisory-notifier';
var MAX_RSS_PAGE_FETCHES = 20;
var NOTION_PAGE_ID = '4131da5a7f3b807c8ad7d57c75bd8d9f';
var NOTION_VERSION = '2022-06-28';

var FEEDS = {
  'Node.js': { feed: { type: 'rss', url: 'https://nodejs.org/en/feed/vulnerability.xml' } },
  'Ruby': { securityOnly: true, feed: { type: 'rss', url: 'https://www.ruby-lang.org/en/feeds/news.rss' } },
  'Ruby on Rails': { feed: { type: 'rss', url: 'https://discuss.rubyonrails.org/c/security-announcements/9.rss' } },
  'Python': { feed: { type: 'rss', url: 'https://mail.python.org/archives/list/security-announce@python.org/feed/' } },
  'PostgreSQL': { securityOnly: true, feed: { type: 'rss', url: 'https://www.postgresql.org/news.rss' } },
  'Next.js': { exact: true, feed: { type: 'github_advisories', repo: 'vercel/next.js', package: 'next' } },
  'Redis': { exact: true, feed: { type: 'github_advisories', repo: 'redis/redis', package: 'redis' } },
  'Bun': { exact: true, feed: { type: 'github_advisories', repo: 'oven-sh/bun', package: 'bun' } },
  'nginx': { exact: true, feed: { type: 'html_headings', url: 'https://nginx.org/en/security_advisories.html' } }
};

var WATCHES = [
  {
    product: 'Node.js',
    feed: { type: 'rss', url: 'https://nodejs.org/en/feed/vulnerability.xml' },
    lines: [
      { series: '22', version: '22.23.4', repos: ['medup-core-service', 'refery', 'data-customer-ops'] },
      { series: '24', version: '24.22.1', repos: ['foro-crm-devops'] }
    ]
  },
  {
    product: 'Ruby',
    securityOnly: true,
    feed: { type: 'rss', url: 'https://www.ruby-lang.org/en/feeds/news.rss' },
    lines: [
      { series: '3.4', version: '3.4.8', repos: ['foro-crm-api'] }
    ]
  },
  {
    product: 'Ruby on Rails',
    feed: { type: 'rss', url: 'https://discuss.rubyonrails.org/c/security-announcements/9.rss' },
    lines: [
      { series: '8.1', version: '8.1.3.1', repos: ['foro-crm-api'] }
    ]
  },
  {
    product: 'Python',
    feed: { type: 'rss', url: 'https://mail.python.org/archives/list/security-announce@python.org/feed/' },
    lines: [
      { series: '3.12', version: '3.12.12', repos: ['data-management-api'] },
      { series: '3.14', version: '3.14', repos: ['medup-drive'] },
      { series: '3.7', version: '3.7.12', repos: ['redash'], eol: true }
    ]
  },
  {
    product: 'PostgreSQL',
    securityOnly: true,
    feed: { type: 'rss', url: 'https://www.postgresql.org/news.rss' },
    lines: [
      { series: '18', version: '18', repos: ['refery', 'medup-drive'] },
      { series: '9.6', version: '9.6.24', repos: ['redash'], eol: true }
    ]
  },
  {
    product: 'Next.js',
    feed: { type: 'github_advisories', repo: 'vercel/next.js', package: 'next' },
    lines: [
      { version: '15.5.18', repos: ['refery'] },
      { version: '16.4.2', repos: ['medup-core-service'] },
      { version: '13.4.5', repos: ['data-customer-ops'], eol: true }
    ]
  },
  {
    product: 'Redis',
    feed: { type: 'github_advisories', repo: 'redis/redis', package: 'redis' },
    lines: [
      { version: '5.0.14', repos: ['redash'], eol: true }
    ]
  },
  {
    product: 'Bun',
    feed: { type: 'github_advisories', repo: 'oven-sh/bun', package: 'bun' },
    lines: [
      { version: '1.1.38', repos: ['data-customer-ops'], eol: true }
    ]
  },
  {
    product: 'nginx',
    feed: { type: 'html_headings', url: 'https://nginx.org/en/security_advisories.html' },
    lines: [
      { version: '1.9.10', repos: ['redash'], eol: true }
    ]
  }
];

function preview() {
  var resolved = resolveWatches();
  var result = gather(resolved.watches);
  if (resolved.note) Logger.log(resolved.note);
  Logger.log('確認表示です。Slack には出しません。');
  Logger.log('合計 ' + result.found.length + ' 件（過去分を含む。まだ投稿しない）');
}

function seed() {
  var resolved = resolveWatches();
  var result = gather(resolved.watches);
  if (result.failed.length) {
    Logger.log('既読にしません。取れなかったものがあります: ' + failedNames(result.failed));
    Logger.log('Slack には出していません。');
    return;
  }
  var ids = [];
  var seen = {};
  result.found.forEach(function (item) {
    if (!item.id || seen[item.id]) return;
    seen[item.id] = true;
    ids.push(item.id);
  });
  saveSeen(ids);
  Logger.log('既読にしました: ' + loadSeenCount() + ' 件');
  Logger.log('Slack には出していません。');
}

function saveSeen(ids) {
  var props = PropertiesService.getScriptProperties();
  var existing = props.getProperties();
  Object.keys(existing).forEach(function (key) {
    if (key.indexOf('seen_ids_') === 0) props.deleteProperty(key);
  });
  var chunk = [];
  var size = 2;
  var index = 0;
  ids.forEach(function (id) {
    var piece = JSON.stringify(id);
    if (size + piece.length + 1 > 8000 && chunk.length) {
      props.setProperty('seen_ids_' + index, JSON.stringify(chunk));
      index++;
      chunk = [];
      size = 2;
    }
    chunk.push(id);
    size += piece.length + 1;
  });
  if (chunk.length || index === 0) {
    props.setProperty('seen_ids_' + index, JSON.stringify(chunk));
  }
}

function loadSeenCount() {
  return Object.keys(loadSeen()).length;
}

function loadSeen() {
  var props = PropertiesService.getScriptProperties().getProperties();
  var seen = {};
  Object.keys(props).forEach(function (key) {
    if (key.indexOf('seen_ids_') !== 0) return;
    JSON.parse(props[key]).forEach(function (id) {
      seen[id] = true;
    });
  });
  return seen;
}

function resolveWatches() {
  var stored = loadStoredWatches();
  var base = stored || WATCHES;
  try {
    var parsed = readNotionWatches();
    if (!parsed.rows.length) throw new Error('監視ありの行がありません');
    var next = buildWatches(parsed.rows);
    var note = '';
    if (parsed.unknown.length) {
      note = '取り方が未定義です: ' + parsed.unknown.join(', ') + '。それ以外は確認しました。';
    }
    if (watchSignature(next) !== watchSignature(base)) {
      saveStoredWatches(next);
      Logger.log('バージョン一覧の更新を保存しました。');
      return { watches: next, note: note };
    }
    Logger.log('バージョン一覧は前回と同じです。');
    if (!stored) saveStoredWatches(base);
    return { watches: base, note: note };
  } catch (error) {
    Logger.log('バージョン一覧を読めませんでした: ' + safeDetail(error));
    if (!stored) saveStoredWatches(WATCHES);
    return {
      watches: base,
      note: 'バージョン一覧を読めなかったので、前回のバージョンで確認しました。'
    };
  }
}

function loadStoredWatches() {
  var raw = PropertiesService.getScriptProperties().getProperty('watch_list');
  if (!raw) return null;
  try {
    var parsed = JSON.parse(raw);
    if (!parsed || !parsed.length) return null;
    return parsed;
  } catch (error) {
    return null;
  }
}

function saveStoredWatches(watches) {
  PropertiesService.getScriptProperties().setProperty('watch_list', JSON.stringify(watches));
}

function watchSignature(watches) {
  return JSON.stringify(watches.map(function (watch) {
    return {
      product: watch.product,
      lines: watch.lines.map(function (line) {
        var item = {
          version: line.version,
          repos: line.repos.slice().sort(compareText),
          eol: !!line.eol
        };
        if (line.series) item.series = line.series;
        return item;
      }).sort(function (a, b) {
        return compareText(a.series || '', b.series || '') || compareText(a.version, b.version);
      })
    };
  }));
}

function compareText(a, b) {
  if (a < b) return -1;
  if (a > b) return 1;
  return 0;
}

function readNotionWatches() {
  var rows = [];
  var unknown = {};
  var sawWatchColumn = false;
  collectTableIds(NOTION_PAGE_ID).forEach(function (tableId) {
    var tableRows = notionChildren(tableId);
    if (!tableRows.length) return;
    var headers = tableRows[0].table_row.cells.map(richText);
    var index = {};
    headers.forEach(function (header, i) {
      index[header.trim()] = i;
    });
    if (index['対象'] === undefined || index['監視'] === undefined) return;
    sawWatchColumn = true;
    tableRows.slice(1).forEach(function (row) {
      var cells = row.table_row.cells;
      if (richText(cells[index['監視']]).trim() !== 'あり') return;
      var product = richText(cells[index['対象']]).trim();
      var repo = richText(cells[index['リポジトリ']]).trim();
      var version = richText(cells[index['バージョン']]).trim();
      if (!product || !repo || !version) return;
      if (!FEEDS[product]) {
        unknown[product] = true;
        return;
      }
      rows.push({
        product: product,
        repo: repo,
        version: version,
        eol: isPastDate(cellDate(cells[index['サポート期限']]))
      });
    });
  });
  if (!sawWatchColumn) throw new Error('監視の列がありません');
  return { rows: rows, unknown: Object.keys(unknown) };
}

function buildWatches(rows) {
  var grouped = {};
  rows.forEach(function (row) {
    var spec = FEEDS[row.product];
    var series = spec.exact ? '' : seriesOf(row.product, row.version);
    var key = [row.product, series, row.version, row.eol ? '1' : '0'].join('|');
    if (!grouped[key]) {
      grouped[key] = {
        product: row.product,
        series: series,
        version: row.version,
        repos: [],
        eol: row.eol
      };
    }
    if (grouped[key].repos.indexOf(row.repo) < 0) grouped[key].repos.push(row.repo);
  });
  var byProduct = {};
  Object.keys(grouped).forEach(function (key) {
    var line = grouped[key];
    if (!byProduct[line.product]) byProduct[line.product] = [];
    var item = { version: line.version, repos: line.repos };
    if (line.series) item.series = line.series;
    if (line.eol) item.eol = true;
    byProduct[line.product].push(item);
  });
  var watches = [];
  Object.keys(FEEDS).forEach(function (product) {
    if (!byProduct[product]) return;
    var watch = {
      product: product,
      feed: JSON.parse(JSON.stringify(FEEDS[product].feed)),
      lines: byProduct[product]
    };
    if (FEEDS[product].securityOnly) watch.securityOnly = true;
    watches.push(watch);
  });
  return watches;
}

function seriesOf(product, version) {
  var parts = String(version).split('.');
  if (product === 'Node.js') return parts[0];
  if (product === 'PostgreSQL') {
    if (parseInt(parts[0], 10) >= 10) return parts[0];
    return parts.slice(0, 2).join('.');
  }
  return parts.slice(0, 2).join('.');
}

function isPastDate(date) {
  if (!date) return false;
  return date < Utilities.formatDate(new Date(), 'Asia/Tokyo', 'yyyy-MM-dd');
}

function cellDate(items) {
  var found = '';
  (items || []).forEach(function (item) {
    if (item.mention && item.mention.type === 'date' && item.mention.date && item.mention.date.start) {
      found = item.mention.date.start;
    }
  });
  if (found) return found.slice(0, 10);
  var match = richText(items).match(/\d{4}-\d{2}-\d{2}/);
  return match ? match[0] : '';
}

function richText(items) {
  return (items || []).map(function (item) {
    if (item.plain_text) return item.plain_text;
    if (item.mention && item.mention.date && item.mention.date.start) return item.mention.date.start;
    return '';
  }).join('');
}

function collectTableIds(blockId) {
  var ids = [];
  notionChildren(blockId).forEach(function (block) {
    if (block.type === 'table') {
      ids.push(block.id);
      return;
    }
    if (block.has_children && block.type !== 'child_page' && block.type !== 'child_database') {
      ids = ids.concat(collectTableIds(block.id));
    }
  });
  return ids;
}

function notionChildren(blockId) {
  var results = [];
  var cursor = '';
  do {
    var url = 'https://api.notion.com/v1/blocks/' + blockId + '/children?page_size=100';
    if (cursor) url += '&start_cursor=' + encodeURIComponent(cursor);
    var body = notionGet(url);
    results = results.concat(body.results || []);
    cursor = body.has_more ? body.next_cursor : '';
  } while (cursor);
  return results;
}

function notionGet(url) {
  var token = (PropertiesService.getScriptProperties().getProperty('NOTION_TOKEN') || '').trim();
  if (!token) throw new Error('NOTION_TOKEN が未設定です');
  var response = UrlFetchApp.fetch(url, {
    muteHttpExceptions: true,
    headers: {
      Authorization: 'Bearer ' + token,
      'Notion-Version': NOTION_VERSION
    }
  });
  if (response.getResponseCode() >= 400) {
    throw new Error('Notion -> ' + response.getResponseCode() + ' ' + response.getContentText().slice(0, 120));
  }
  return JSON.parse(response.getContentText());
}

function post() {
  var resolved = resolveWatches();
  var result = gather(resolved.watches);
  var config = slackConfig();
  if (result.failed.length) {
    var text = 'セキュリティ告知の取得に失敗しました\n' +
      result.failed.map(function (item) {
        return item.product + ': ' + item.detail;
      }).join('\n') +
      '\nこの回は新しい告知を確認できていません。';
    if (resolved.note) text = resolved.note + '\n' + text;
    Logger.log(text);
    if (!config.token || !config.channel) {
      Logger.log('Slack には出していません。');
      return;
    }
    postSlack(config.token, config.channel, text);
    Logger.log('取得失敗を Slack に出しました。');
    return;
  }
  var seen = loadSeen();
  var fresh = [];
  result.found.forEach(function (item) {
    if (!item.id || seen[item.id]) return;
    fresh.push(item);
  });
  if (!fresh.length) {
    if (resolved.note) {
      Logger.log(resolved.note);
      if (!config.token || !config.channel) {
        Logger.log('Slack には出していません。');
        return;
      }
      postSlack(config.token, config.channel, resolved.note);
      Logger.log('一覧の注意を Slack に出しました。');
      return;
    }
    Logger.log('新しい告知はありません。');
    Logger.log('Slack には出していません。');
    return;
  }
  if (!config.token || !config.channel) {
    Logger.log('投稿しません。SLACK_BOT_TOKEN または SLACK_CHANNEL が未設定です。');
    Logger.log('Slack には出していません。');
    return;
  }
  if (resolved.note) {
    postSlack(config.token, config.channel, resolved.note);
    Logger.log(resolved.note);
  }
  fresh.forEach(function (item) {
    postSlack(config.token, config.channel, item.text);
    seen[item.id] = true;
    saveSeen(Object.keys(seen));
    Logger.log(item.text.split('\n')[0]);
  });
  Logger.log('投稿しました: ' + fresh.length + ' 件');
}

function failedNames(failed) {
  return failed.map(function (item) {
    return item.product;
  }).join(', ');
}

function slackConfig() {
  var props = PropertiesService.getScriptProperties();
  return {
    token: (props.getProperty('SLACK_BOT_TOKEN') || '').trim(),
    channel: (props.getProperty('SLACK_CHANNEL') || '').trim()
  };
}

function safeDetail(error) {
  return String(error)
    .replace(/ghp_[A-Za-z0-9]+/g, '[token]')
    .replace(/github_pat_[A-Za-z0-9_]+/g, '[token]')
    .replace(/xoxb-[A-Za-z0-9-]+/g, '[token]')
    .replace(/ntn_[A-Za-z0-9]+/g, '[token]')
    .replace(/secret_[A-Za-z0-9]+/g, '[token]')
    .slice(0, 180);
}

function postSlack(token, channel, text) {
  var response = UrlFetchApp.fetch('https://slack.com/api/chat.postMessage', {
    method: 'post',
    contentType: 'application/json; charset=utf-8',
    headers: { Authorization: 'Bearer ' + token },
    payload: JSON.stringify({ channel: channel, text: text }),
    muteHttpExceptions: true
  });
  var body = JSON.parse(response.getContentText());
  if (!body.ok) throw new Error(body.error || 'Slack への投稿に失敗しました');
}

function gather(watches) {
  var found = [];
  var failed = [];
  (watches || WATCHES).forEach(function (watch) {
    try {
      var items = collect(watch);
      Logger.log(watch.product + ' ' + items.length);
      found = found.concat(items);
    } catch (error) {
      failed.push({ product: watch.product, detail: safeDetail(error) });
      Logger.log(watch.product + ' の取得失敗: ' + safeDetail(error));
    }
  });
  return { found: found, failed: failed };
}

function collect(watch) {
  var kind = watch.feed.type;
  if (kind === 'rss') return rssItems(watch);
  if (kind === 'github_advisories') return githubItems(watch);
  if (kind === 'html_headings') return nginxItems(watch);
  throw new Error('未知の取得方法です: ' + kind);
}

function rssItems(watch) {
  var response = fetchResponse(watch.feed.url);
  var doc = XmlService.parse(response.getContentText());
  var items = [];
  var fetches = 0;
  childrenByName(doc.getRootElement(), 'item').forEach(function (entry) {
    var title = stripHtml(childText(entry, 'title'));
    var link = childText(entry, 'link');
    var body = stripHtml(childText(entry, 'description') || childText(entry, 'summary'));
    var text = title + '\n' + body;
    if (watch.product === 'PostgreSQL' && title.indexOf('PostgreSQL') !== 0) return;
    if (watch.securityOnly && !isSecurityText(text)) return;
    var lines = matchedLines(watch, text);
    if (!lines.length && !body && link && fetches < MAX_RSS_PAGE_FETCHES) {
      fetches++;
      text = title + '\n' + stripHtml(fetchResponse(link).getContentText());
      lines = matchedLines(watch, text);
    }
    if (!lines.length) return;
    items.push({
      id: childText(entry, 'guid') || link,
      text: formatMessage(watch.product, title || '(無題)', lines, link)
    });
  });
  return items;
}

function githubItems(watch) {
  var url = 'https://api.github.com/repos/' + watch.feed.repo +
    '/security-advisories?per_page=30&state=published';
  var githubHeaders = { Accept: 'application/vnd.github+json' };
  var githubToken = PropertiesService.getScriptProperties().getProperty('GITHUB_TOKEN');
  if (githubToken) githubHeaders.Authorization = 'Bearer ' + githubToken.trim();
  var advisories = JSON.parse(fetchResponse(url, githubHeaders).getContentText());
  var packageName = watch.feed.package.toLowerCase();
  var items = [];
  advisories.forEach(function (advisory) {
    var affected = [];
    var seen = {};
    (advisory.vulnerabilities || []).forEach(function (vuln) {
      var name = ((vuln.package || {}).name || '').toLowerCase();
      if (name !== packageName) return;
      var rawRange = vuln.vulnerable_version_range || '';
      watch.lines.forEach(function (line) {
        var key = line.version + '|' + line.repos.join(',');
        if (seen[key]) return;
        if (!versionInSpecifier(line.version, rawRange)) return;
        seen[key] = true;
        affected.push(line);
      });
    });
    if (!affected.length) return;
    items.push({
      id: advisory.ghsa_id || advisory.html_url || '',
      text: formatMessage(
        watch.product,
        advisory.summary || advisory.ghsa_id || '(無題)',
        affected,
        advisory.html_url || ''
      )
    });
  });
  return items;
}

function nginxItems(watch) {
  var html = fetchResponse(watch.feed.url).getContentText();
  var pattern = /<li><p>([\s\S]*?)<\/p><\/li>/g;
  var items = [];
  var raw;
  while ((raw = pattern.exec(html)) !== null) {
    var block = raw[1];
    var text = stripHtml(block);
    var cve = text.match(/CVE-\d{4}-\d+/);
    var title = text.split('\n')[0];
    var linkMatch = block.match(/href="([^"]+)"/);
    var link = linkMatch ? linkMatch[1] : watch.feed.url;
    if (cve) title = title + ' (' + cve[0] + ')';
    var lines = watch.lines.filter(function (line) {
      return nginxAffects(text, line.version);
    });
    if (!lines.length) continue;
    items.push({
      id: cve ? cve[0] : title,
      text: formatMessage(watch.product, title, lines, link)
    });
  }
  return items;
}

function matchedLines(watch, text) {
  var found = [];
  watch.lines.forEach(function (line) {
    if (line.series && seriesRegex(line.series, watch.product).test(text)) {
      found.push(line);
    } else if (!line.series && nginxAffects(text, line.version)) {
      found.push(line);
    }
  });
  return found;
}

function formatMessage(product, title, lines, url) {
  var groups = lines.map(function (line) {
    var note = line.eol ? '。修正版は出ない' : '';
    return line.repos.join(', ') + '（' + line.version + '）' + note;
  });
  return product + '  ' + title + '\n該当: ' + groups.join('; ') + '\n' + url;
}

function fetchResponse(url, extraHeaders) {
  var headers = { 'User-Agent': USER_AGENT };
  if (extraHeaders) {
    Object.keys(extraHeaders).forEach(function (key) {
      headers[key] = extraHeaders[key];
    });
  }
  var response = UrlFetchApp.fetch(url, {
    muteHttpExceptions: true,
    followRedirects: true,
    headers: headers
  });
  if (response.getResponseCode() >= 400) {
    throw new Error(url + ' -> ' + response.getResponseCode() + ' ' + response.getContentText().slice(0, 120));
  }
  return response;
}

function childrenByName(element, name) {
  var found = [];
  element.getChildren().forEach(function (child) {
    if (child.getName() === name) found.push(child);
    else found = found.concat(childrenByName(child, name));
  });
  return found;
}

function childText(element, name) {
  var children = element.getChildren();
  for (var i = 0; i < children.length; i++) {
    if (children[i].getName() === name) return children[i].getText() || '';
  }
  return '';
}

function stripHtml(text) {
  return String(text || '')
    .replace(/<br\s*\/?>/ig, '\n')
    .replace(/<[^>]+>/g, ' ')
    .replace(/[ \t]+/g, ' ')
    .trim();
}

function isSecurityText(text) {
  return /\b(security|cve-\d{4}-\d+)\b/i.test(text);
}

function seriesRegex(series, product) {
  if (product === 'PostgreSQL' && /^\d+$/.test(series)) {
    return new RegExp('(?:\\bPostgreSQL\\s+' + series + '\\b|\\b' + series + '\\.\\d+\\b)');
  }
  if (/^\d+$/.test(series)) return new RegExp('\\b' + series + '\\.\\d+\\b');
  return new RegExp('\\b' + series.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '(?:\\.\\d+)*\\b');
}

function versionParts(version) {
  return String(version).split('.').map(function (part) {
    var number = parseInt(part, 10);
    return isNaN(number) ? 0 : number;
  });
}

function compareVersions(left, right) {
  var a = versionParts(left);
  var b = versionParts(right);
  var length = Math.max(a.length, b.length);
  for (var i = 0; i < length; i++) {
    var av = a[i] || 0;
    var bv = b[i] || 0;
    if (av < bv) return -1;
    if (av > bv) return 1;
  }
  return 0;
}

function versionInSpecifier(version, rawRange) {
  var text = String(rawRange || '').replace(/,/g, ' ').trim();
  var match = text.match(/^(>=|<=|==|!=|>|<)\s*(\d+(?:\.\d+)*)(?:[-+][0-9A-Za-z.]+)?$/);
  if (!match) return false;
  var cmp = compareVersions(version, match[2]);
  if (match[1] === '>=') return cmp >= 0;
  if (match[1] === '<=') return cmp <= 0;
  if (match[1] === '>') return cmp > 0;
  if (match[1] === '<') return cmp < 0;
  if (match[1] === '==') return cmp === 0;
  if (match[1] === '!=') return cmp !== 0;
  return false;
}

function nginxAffects(text, version) {
  var blob = '';
  String(text).split('\n').forEach(function (line) {
    if (/^\s*not\s+vulnerable/i.test(line)) return;
    var match = line.match(/vulnerable:\s*(.+)/i);
    if (match) blob = match[1];
  });
  if (!blob) return false;
  if (/\ball\b/i.test(blob)) return true;
  var parts = blob.split(',');
  for (var i = 0; i < parts.length; i++) {
    var span = parts[i].trim().replace(/\.$/, '').match(/^(\d+(?:\.\d+)*)-(\d+(?:\.\d+)*)$/);
    if (!span) continue;
    if (compareVersions(version, span[1]) >= 0 && compareVersions(version, span[2]) <= 0) {
      return true;
    }
  }
  return false;
}
