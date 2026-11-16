import Foundation

/// Страница загрузки, которую открывают в браузере на компьютере.
enum WebUploadPage {
    static let html = #"""
<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>PlayMyDisk — загрузка музыки</title>
<style>
  body { margin: 0; font-family: -apple-system, Segoe UI, Roboto, sans-serif; background: #101215; color: #ECEEF1; }
  .wrap { max-width: 760px; margin: 0 auto; padding: 32px 20px; }
  h1 { margin: 0 0 6px; font-size: 26px; }
  .sub { color: #9BA3AE; margin-bottom: 24px; }
  .card { background: #181B20; border: 1px solid #2A2F36; border-radius: 14px; padding: 18px; margin-bottom: 16px; }
  label { display: block; color: #9BA3AE; font-size: 13px; margin-bottom: 6px; }
  input, select { width: 100%; box-sizing: border-box; height: 42px; border-radius: 10px; border: 1px solid #2E333A; background: #23272D; color: #ECEEF1; font-size: 16px; padding: 0 12px; }
  #pin { width: 140px; letter-spacing: 6px; font-size: 22px; text-align: center; }
  .drop { border: 2px dashed #3A4048; border-radius: 14px; padding: 40px 16px; text-align: center; color: #9BA3AE; cursor: pointer; }
  .drop.over { border-color: #FF8A1F; color: #FF8A1F; background: #2B2219; }
  .btn { display: inline-block; margin-top: 12px; background: #FF8A1F; color: #1A0E00; border: 0; border-radius: 10px; padding: 10px 18px; font-weight: 700; font-size: 15px; cursor: pointer; }
  .row { display: flex; align-items: center; gap: 10px; padding: 8px 0; border-bottom: 1px solid #2A2F36; font-size: 14px; }
  .row .name { flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .bar { width: 160px; height: 8px; background: #2E333A; border-radius: 4px; overflow: hidden; }
  .bar > div { height: 100%; width: 0; background: #FF8A1F; }
  .st { width: 90px; text-align: right; color: #9BA3AE; }
  .ok { color: #6CFF7E; } .err { color: #FF5A5F; }
  .hint { color: #9BA3AE; font-size: 13px; }
</style>
</head>
<body>
<div class="wrap">
  <h1>PlayMyDisk</h1>
  <div class="sub">Загрузка музыки на iPhone по Wi-Fi · Upload music to iPhone over Wi-Fi</div>

  <div class="card">
    <label for="pin">PIN с экрана iPhone · PIN shown on the iPhone</label>
    <input id="pin" maxlength="4" inputmode="numeric" autocomplete="off">
    <div style="height:12px"></div>
    <label for="folder">Папка · Folder</label>
    <select id="folder"><option value="">Музыка (корень)</option></select>
  </div>

  <div class="card">
    <div id="drop" class="drop">
      Перетащите файлы сюда или нажмите, чтобы выбрать<br>
      <span class="hint">Drag files here or click to choose · MP3, M4A, M4B, FLAC, WAV, AIFF, CAF…</span>
    </div>
    <input id="files" type="file" multiple style="display:none">
  </div>

  <div class="card">
    <div id="queue" class="hint">Очередь пуста · Queue is empty</div>
  </div>
  <div class="hint">Не сворачивайте приложение на iPhone, пока идёт загрузка. · Keep the app open on the iPhone while uploading.</div>
</div>
<script>
const allowed = ["mp3","aac","m4a","m4b","m4r","flac","wav","aiff","aif","aifc","caf","m4p","aa","aax"];
const pinInput = document.getElementById("pin");
const folderSelect = document.getElementById("folder");
const drop = document.getElementById("drop");
const filesInput = document.getElementById("files");
const queueBox = document.getElementById("queue");
let queue = [];
let busy = false;

try { pinInput.value = localStorage.getItem("pmd_pin") || ""; } catch (e) {}
pinInput.addEventListener("input", () => {
  try { localStorage.setItem("pmd_pin", pinInput.value); } catch (e) {}
  if (pinInput.value.length === 4) loadFolders();
});

function loadFolders() {
  fetch("/folders", { headers: { "X-PIN": pinInput.value } })
    .then(r => { if (!r.ok) throw new Error(r.status); return r.json(); })
    .then(list => {
      const current = folderSelect.value;
      folderSelect.innerHTML = "";
      list.forEach(path => {
        const opt = document.createElement("option");
        opt.value = path;
        opt.textContent = path === "" ? "Музыка (корень)" : "Музыка / " + path;
        folderSelect.appendChild(opt);
      });
      folderSelect.value = current;
    })
    .catch(() => {});
}
if (pinInput.value.length === 4) loadFolders();

drop.addEventListener("click", () => filesInput.click());
drop.addEventListener("dragover", e => { e.preventDefault(); drop.classList.add("over"); });
drop.addEventListener("dragleave", () => drop.classList.remove("over"));
drop.addEventListener("drop", e => { e.preventDefault(); drop.classList.remove("over"); add(e.dataTransfer.files); });
filesInput.addEventListener("change", () => { add(filesInput.files); filesInput.value = ""; });

function add(fileList) {
  if (queueBox.classList.contains("hint")) { queueBox.classList.remove("hint"); queueBox.innerHTML = ""; }
  for (const file of fileList) {
    const ext = file.name.split(".").pop().toLowerCase();
    const row = document.createElement("div");
    row.className = "row";
    row.innerHTML = '<div class="name"></div><div class="bar"><div></div></div><div class="st"></div>';
    row.querySelector(".name").textContent = file.name;
    queueBox.appendChild(row);
    if (!allowed.includes(ext)) {
      row.querySelector(".st").textContent = "формат?";
      row.querySelector(".st").className = "st err";
      continue;
    }
    row.querySelector(".st").textContent = "в очереди";
    queue.push({ file, row, folder: folderSelect.value });
  }
  next();
}

function next() {
  if (busy || queue.length === 0) return;
  if (pinInput.value.length !== 4) { alert("Введите PIN с экрана iPhone · Enter the PIN from the iPhone"); return; }
  busy = true;
  const item = queue.shift();
  const st = item.row.querySelector(".st");
  const bar = item.row.querySelector(".bar > div");
  const xhr = new XMLHttpRequest();
  const url = "/upload?path=" + encodeURIComponent(item.folder) + "&name=" + encodeURIComponent(item.file.name);
  xhr.open("PUT", url);
  xhr.setRequestHeader("X-PIN", pinInput.value);
  xhr.upload.onprogress = e => {
    if (e.lengthComputable) {
      const p = Math.round(e.loaded / e.total * 100);
      bar.style.width = p + "%";
      st.textContent = p + "%";
    }
  };
  xhr.onload = () => {
    if (xhr.status === 200) { bar.style.width = "100%"; st.textContent = "готово"; st.className = "st ok"; }
    else if (xhr.status === 401) { st.textContent = "PIN?"; st.className = "st err"; }
    else { st.textContent = "ошибка " + xhr.status; st.className = "st err"; }
    busy = false; next();
  };
  xhr.onerror = () => { st.textContent = "нет связи"; st.className = "st err"; busy = false; next(); };
  st.textContent = "0%";
  xhr.send(item.file);
}
</script>
</body>
</html>
"""#
}
