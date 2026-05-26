<%@ Page Language="C#" CodePage="65001" %>
<%@ Import Namespace="System" %>
<%@ Import Namespace="System.IO" %>
<%@ Import Namespace="System.Web" %>
<%@ Import Namespace="System.Collections.Generic" %>
<script runat="server">
    string Root {
        get { return Server.MapPath("files"); }
    }

    string CleanRel(string rel) {
        if (String.IsNullOrWhiteSpace(rel)) return "";
        rel = rel.Replace('\\', '/').Trim('/');
        string full = Path.GetFullPath(Path.Combine(Root, rel.Replace('/', Path.DirectorySeparatorChar)));
        string rootFull = Path.GetFullPath(Root);
        if (!full.Equals(rootFull, StringComparison.OrdinalIgnoreCase) &&
            !full.StartsWith(rootFull.TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)) {
            throw new InvalidOperationException("Bad path");
        }
        if (!Directory.Exists(full) && !File.Exists(full)) return rel;
        return full.Substring(rootFull.Length).TrimStart(Path.DirectorySeparatorChar).Replace(Path.DirectorySeparatorChar, '/');
    }

    string RelToFull(string rel) {
        rel = CleanRel(rel);
        string full = Path.GetFullPath(Path.Combine(Root, rel.Replace('/', Path.DirectorySeparatorChar)));
        string rootFull = Path.GetFullPath(Root);
        if (!full.Equals(rootFull, StringComparison.OrdinalIgnoreCase) &&
            !full.StartsWith(rootFull.TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)) {
            throw new InvalidOperationException("Bad path");
        }
        return full;
    }

    string H(string value) {
        return Server.HtmlEncode(value ?? "");
    }

    string U(string value) {
        return HttpUtility.UrlEncode(value ?? "");
    }

    string JoinRel(string parent, string name) {
        return String.IsNullOrEmpty(parent) ? name : parent.TrimEnd('/') + "/" + name;
    }

    string SizeText(long bytes) {
        string[] units = { "B", "KB", "MB", "GB" };
        double size = bytes;
        int unit = 0;
        while (size >= 1024 && unit < units.Length - 1) { size /= 1024; unit++; }
        return unit == 0 ? bytes + " B" : size.ToString("0.##") + " " + units[unit];
    }

    bool BadName(string name) {
        if (String.IsNullOrWhiteSpace(name)) return true;
        if (name == "." || name == "..") return true;
        return name.IndexOfAny(Path.GetInvalidFileNameChars()) >= 0 || name.Contains("/") || name.Contains("\\");
    }

    protected override void OnLoad(EventArgs e) {
        base.OnLoad(e);
        Directory.CreateDirectory(Root);
        string rel = CleanRel(Request["p"]);
        string current = RelToFull(rel);
        if (!Directory.Exists(current)) {
            rel = "";
            current = Root;
        }

        string action = Request["action"];
        if (String.Equals(action, "download", StringComparison.OrdinalIgnoreCase)) {
            string fileRel = CleanRel(Request["file"]);
            string file = RelToFull(fileRel);
            if (!File.Exists(file)) {
                Response.StatusCode = 404;
                Response.Write("File not found");
                Response.End();
                return;
            }
            Response.Clear();
            Response.ContentType = "application/octet-stream";
            Response.AddHeader("Content-Disposition", "attachment; filename=\"" + Path.GetFileName(file).Replace("\"", "") + "\"");
            Response.AddHeader("Content-Length", new FileInfo(file).Length.ToString());
            Response.TransmitFile(file);
            Response.End();
            return;
        }

        string notice = "";
        if (Request.HttpMethod == "POST") {
            string postAction = Request.Form["action"];
            try {
                if (postAction == "uploadchunk") {
                    string fileName = Path.GetFileName(Request.Form["fileName"] ?? "");
                    string uploadId = Request.Form["uploadId"] ?? "";
                    int chunkIndex = Int32.Parse(Request.Form["chunkIndex"] ?? "0");
                    int totalChunks = Int32.Parse(Request.Form["totalChunks"] ?? "1");
                    if (BadName(fileName)) throw new Exception("Invalid file name");
                    if (uploadId.Length == 0 || uploadId.IndexOfAny(Path.GetInvalidFileNameChars()) >= 0) throw new Exception("Invalid upload id");
                    HttpPostedFile chunk = Request.Files["chunk"];
                    if (chunk == null || chunk.ContentLength <= 0) throw new Exception("Missing chunk");
                    string finalPath = Path.Combine(current, fileName);
                    string tempPath = Path.Combine(current, "." + fileName + "." + uploadId + ".uploading");
                    if (chunkIndex == 0 && File.Exists(tempPath)) File.Delete(tempPath);
                    using (FileStream fs = new FileStream(tempPath, FileMode.Append, FileAccess.Write, FileShare.None)) {
                        chunk.InputStream.CopyTo(fs);
                    }
                    if (chunkIndex == totalChunks - 1) {
                        if (File.Exists(finalPath)) File.Delete(finalPath);
                        File.Move(tempPath, finalPath);
                    }
                    Response.ContentType = "text/plain; charset=utf-8";
                    Response.Write("OK");
                    Response.End();
                    return;
                } else if (postAction == "mkdir") {
                    string folder = (Request.Form["folder"] ?? "").Trim();
                    if (BadName(folder)) throw new Exception("\u6587\u4EF6\u5939\u540D\u79F0\u65E0\u6548");
                    Directory.CreateDirectory(Path.Combine(current, folder));
                    notice = "\u6587\u4EF6\u5939\u5DF2\u521B\u5EFA\uFF1A" + folder;
                } else if (postAction == "upload") {
                    HttpPostedFile upload = Request.Files["upload"];
                    if (upload == null || upload.ContentLength <= 0) throw new Exception("\u8BF7\u5148\u9009\u62E9\u6587\u4EF6");
                    string fileName = Path.GetFileName(upload.FileName);
                    if (BadName(fileName)) throw new Exception("\u6587\u4EF6\u540D\u79F0\u65E0\u6548");
                    upload.SaveAs(Path.Combine(current, fileName));
                    notice = "\u4E0A\u4F20\u6210\u529F\uFF1A" + fileName;
                } else if (postAction == "delete") {
                    string targetRel = CleanRel(Request.Form["target"]);
                    string target = RelToFull(targetRel);
                    if (String.IsNullOrEmpty(targetRel)) throw new Exception("\u5220\u9664\u76EE\u6807\u65E0\u6548");
                    if (File.Exists(target)) {
                        File.Delete(target);
                        notice = "\u5DF2\u5220\u9664\u6587\u4EF6\uFF1A" + Path.GetFileName(target);
                    } else if (Directory.Exists(target)) {
                        Directory.Delete(target, true);
                        notice = "\u5DF2\u5220\u9664\u6587\u4EF6\u5939\uFF1A" + Path.GetFileName(target);
                    } else {
                        throw new Exception("\u5220\u9664\u76EE\u6807\u4E0D\u5B58\u5728");
                    }
                }
            } catch (Exception ex) {
                notice = "\u9519\u8BEF\uFF1A" + ex.Message;
            }
        }

        RenderPage(rel, current, notice);
    }

    void RenderPage(string rel, string current, string notice) {
        Response.ContentType = "text/html; charset=utf-8";
        Response.ContentEncoding = System.Text.Encoding.UTF8;
        var dirs = new List<DirectoryInfo>(new DirectoryInfo(current).GetDirectories());
        var files = new List<FileInfo>(new DirectoryInfo(current).GetFiles());
        dirs.Sort((a, b) => StringComparer.OrdinalIgnoreCase.Compare(a.Name, b.Name));
        files.Sort((a, b) => StringComparer.OrdinalIgnoreCase.Compare(a.Name, b.Name));
        string parent = "";
        if (!String.IsNullOrEmpty(rel)) {
            int slash = rel.LastIndexOf('/');
            parent = slash >= 0 ? rel.Substring(0, slash) : "";
        }
        string appLabel = H(Request.Url.Host + Request.ApplicationPath.TrimEnd('/'));

        Response.Write("<!doctype html><html><head><meta charset='utf-8'><title>" + appLabel + " &#x6587;&#x4EF6;&#x67DC;</title>");
        Response.Write("<style>");
        Response.Write("body{margin:0;background:#008080;color:#000;font:13px 'MS Sans Serif',Tahoma,Arial,sans-serif;}");
        Response.Write(".desk{padding:18px}.win{max-width:1060px;margin:0 auto;border:2px solid #fff;border-right-color:#404040;border-bottom-color:#404040;background:#c0c0c0;box-shadow:3px 3px 0 #000}.bar{background:linear-gradient(90deg,#000080,#1084d0);color:#fff;font-weight:bold;padding:4px 8px}.inner{padding:10px;border:2px solid #808080;border-right-color:#fff;border-bottom-color:#fff}.toolbar{display:flex;gap:8px;flex-wrap:wrap;align-items:end;margin-bottom:10px}.panel{border:2px solid #808080;border-right-color:#fff;border-bottom-color:#fff;background:#d4d0c8;padding:8px}.btn,input[type=file],input[type=text]{font:13px 'MS Sans Serif',Tahoma,Arial,sans-serif}.btn{border:2px solid #fff;border-right-color:#404040;border-bottom-color:#404040;background:#c0c0c0;padding:4px 10px;color:#000;text-decoration:none;cursor:pointer;display:inline-block}.btn:active{border-color:#404040 #fff #fff #404040}.danger{color:#800000}.inline{display:inline;margin-left:6px}.path{background:#fff;border:2px inset #c0c0c0;padding:5px;margin-bottom:10px}.notice{background:#ffffcc;border:1px solid #808000;padding:6px;margin-bottom:10px}.progress{height:18px;background:#fff;border:2px inset #c0c0c0;margin-top:8px;min-width:260px}.progress span{display:block;height:100%;width:0;background:#000080}.list{width:100%;border-collapse:collapse;background:#fff}.list th{background:#000080;color:#fff;text-align:left;padding:5px}.list td{padding:5px;border-bottom:1px solid #ddd}.list tr:hover td{background:#dbe9ff}.name a{color:#000080;text-decoration:none}.name a:hover{text-decoration:underline}.muted{color:#555}.foot{margin-top:10px;color:#333}</style>");
        Response.Write("</head><body><div class='desk'><div class='win'><div class='bar'>&#x6587;&#x4EF6;&#x67DC; - " + appLabel + "</div><div class='inner'>");
        Response.Write("<div class='path'><b>&#x5F53;&#x524D;&#x4F4D;&#x7F6E;&#xFF1A;</b> /a/files/" + H(rel) + "</div>");
        if (!String.IsNullOrEmpty(notice)) Response.Write("<div class='notice'>" + H(notice) + "</div>");
        Response.Write("<div class='toolbar'>");
        Response.Write("<form id='uploadForm' class='panel' method='post' enctype='multipart/form-data'><input type='hidden' name='action' value='upload'><input type='hidden' id='uploadPath' name='p' value='" + H(rel) + "'><div><b>&#x4E0A;&#x4F20;&#x6587;&#x4EF6;</b></div><input type='file' id='uploadFile' name='upload'> <button class='btn' type='submit'>&#x4E0A;&#x4F20;</button><div class='progress'><span id='uploadBar'></span></div><div id='uploadStatus' class='muted'></div></form>");
        Response.Write("<form class='panel' method='post'><input type='hidden' name='action' value='mkdir'><input type='hidden' name='p' value='" + H(rel) + "'><div><b>&#x65B0;&#x5EFA;&#x6587;&#x4EF6;&#x5939;</b></div><input type='text' name='folder' placeholder='&#x6587;&#x4EF6;&#x5939;&#x540D;&#x79F0;'> <button class='btn' type='submit'>&#x521B;&#x5EFA;</button></form>");
        Response.Write("</div>");
        Response.Write("<table class='list'><thead><tr><th>&#x540D;&#x79F0;</th><th>&#x7C7B;&#x578B;</th><th>&#x5927;&#x5C0F;</th><th>&#x4FEE;&#x6539;&#x65F6;&#x95F4;</th><th>&#x64CD;&#x4F5C;</th></tr></thead><tbody>");
        if (!String.IsNullOrEmpty(rel)) {
            Response.Write("<tr><td class='name'><a href='?p=" + U(parent) + "'>[&#x8FD4;&#x56DE;&#x4E0A;&#x7EA7;]</a></td><td>&#x6587;&#x4EF6;&#x5939;</td><td class='muted'>-</td><td class='muted'>-</td><td></td></tr>");
        }
        foreach (var d in dirs) {
            string child = JoinRel(rel, d.Name);
            Response.Write("<tr><td class='name'><a href='?p=" + U(child) + "'>[&#x76EE;&#x5F55;] " + H(d.Name) + "</a></td><td>&#x6587;&#x4EF6;&#x5939;</td><td class='muted'>-</td><td>" + H(d.LastWriteTime.ToString("yyyy-MM-dd HH:mm")) + "</td><td><a class='btn' href='?p=" + U(child) + "'>&#x6253;&#x5F00;</a><form class='inline' method='post' onsubmit=\"return confirm('\\u786E\\u5B9A\\u5220\\u9664\\u8FD9\\u4E2A\\u6587\\u4EF6\\u5939\\u5417\\uFF1F');\"><input type='hidden' name='action' value='delete'><input type='hidden' name='p' value='" + H(rel) + "'><input type='hidden' name='target' value='" + H(child) + "'><button class='btn danger' type='submit'>&#x5220;&#x9664;</button></form></td></tr>");
        }
        foreach (var f in files) {
            string child = JoinRel(rel, f.Name);
            Response.Write("<tr><td class='name'>" + H(f.Name) + "</td><td>&#x6587;&#x4EF6;</td><td>" + H(SizeText(f.Length)) + "</td><td>" + H(f.LastWriteTime.ToString("yyyy-MM-dd HH:mm")) + "</td><td><a class='btn' href='?action=download&file=" + U(child) + "'>&#x4E0B;&#x8F7D;</a><form class='inline' method='post' onsubmit=\"return confirm('\\u786E\\u5B9A\\u5220\\u9664\\u8FD9\\u4E2A\\u6587\\u4EF6\\u5417\\uFF1F');\"><input type='hidden' name='action' value='delete'><input type='hidden' name='p' value='" + H(rel) + "'><input type='hidden' name='target' value='" + H(child) + "'><button class='btn danger' type='submit'>&#x5220;&#x9664;</button></form></td></tr>");
        }
        if (dirs.Count == 0 && files.Count == 0) Response.Write("<tr><td colspan='5' class='muted'>&#x8FD9;&#x4E2A;&#x6587;&#x4EF6;&#x5939;&#x662F;&#x7A7A;&#x7684;&#x3002;</td></tr>");
        Response.Write("</tbody></table><div class='foot'>&#x4E0A;&#x4F20;&#x4E0A;&#x9650;&#xFF1A;10 GB&#x3002;&#x5927;&#x6587;&#x4EF6;&#x4F1A;&#x81EA;&#x52A8;&#x5206;&#x7247;&#x4E0A;&#x4F20;&#x3002;</div>");
        Response.Write("<scr" + "ipt>(function(){var form=document.getElementById('uploadForm'),fileInput=document.getElementById('uploadFile'),bar=document.getElementById('uploadBar'),status=document.getElementById('uploadStatus'),path=document.getElementById('uploadPath').value;form.onsubmit=function(e){var file=fileInput.files&&fileInput.files[0];if(!file){return true;}e.preventDefault();var max=10*1024*1024*1024;if(file.size>max){alert('\\u6587\\u4EF6\\u8D85\\u8FC7 10GB');return false;}var chunkSize=64*1024*1024,total=Math.ceil(file.size/chunkSize),id=Date.now().toString(36)+Math.random().toString(36).slice(2),i=0;function send(){var start=i*chunkSize,end=Math.min(file.size,start+chunkSize),fd=new FormData();fd.append('action','uploadchunk');fd.append('p',path);fd.append('fileName',file.name);fd.append('uploadId',id);fd.append('chunkIndex',i);fd.append('totalChunks',total);fd.append('chunk',file.slice(start,end),file.name+'.part');var xhr=new XMLHttpRequest();xhr.open('POST',location.pathname+location.search,true);xhr.onload=function(){if(xhr.status>=200&&xhr.status<300){i++;var pct=Math.floor(i*100/total);bar.style.width=pct+'%';status.innerHTML='&#x4E0A;&#x4F20;&#x8FDB;&#x5EA6;&#xFF1A;'+pct+'%';if(i<total){send();}else{status.innerHTML='&#x4E0A;&#x4F20;&#x5B8C;&#x6210;&#xFF0C;&#x6B63;&#x5728;&#x5237;&#x65B0;...';location.reload();}}else{alert('\\u4E0A\\u4F20\\u5931\\u8D25\\uFF1A'+xhr.status);}};xhr.onerror=function(){alert('\\u4E0A\\u4F20\\u5931\\u8D25');};xhr.send(fd);}send();return false;};})();</scr" + "ipt>");
        Response.Write("</div></div></div></body></html>");
        Response.End();
    }
</script>
