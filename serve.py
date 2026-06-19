#!/usr/bin/env python3
from __future__ import annotations

import email.utils
import html
import os
import posixpath
import re
import shutil
import sys
import urllib.parse
from http import HTTPStatus
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer


class RangeRequestHandler(SimpleHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def send_head(self):
        path = self.translate_path(self.path)

        if os.path.isdir(path):
            parts = urllib.parse.urlsplit(self.path)
            if not parts.path.endswith("/"):
                self.send_response(HTTPStatus.MOVED_PERMANENTLY)
                new_parts = (parts[0], parts[1], parts[2] + "/", parts[3], parts[4])
                self.send_header("Location", urllib.parse.urlunsplit(new_parts))
                self.send_header("Content-Length", "0")
                self.end_headers()
                return None
            for index in ("index.html", "index.htm"):
                index_path = os.path.join(path, index)
                if os.path.exists(index_path):
                    path = index_path
                    break
            else:
                return self.list_directory(path)

        ctype = self.guess_type(path)
        try:
            file_obj = open(path, "rb")
        except OSError:
            self.send_error(HTTPStatus.NOT_FOUND, "File not found")
            return None

        try:
            fs = os.fstat(file_obj.fileno())
            file_len = fs.st_size
            range_header = self.headers.get("Range")
            start = 0
            end = file_len - 1

            if_range = self.headers.get("If-Range")
            if if_range:
                etag = f'"{fs.st_mtime}-{file_len}"'
                last_modified = email.utils.formatdate(fs.st_mtime, usegmt=True)
                if if_range not in (etag, last_modified):
                    range_header = None

            if range_header:
                match = re.fullmatch(r"bytes=(\d*)-(\d*)", range_header.strip())
                if not match:
                    self.send_error(HTTPStatus.REQUESTED_RANGE_NOT_SATISFIABLE)
                    file_obj.close()
                    return None

                start_raw, end_raw = match.groups()
                if start_raw == "" and end_raw == "":
                    self.send_error(HTTPStatus.REQUESTED_RANGE_NOT_SATISFIABLE)
                    file_obj.close()
                    return None

                if start_raw == "":
                    suffix_len = int(end_raw)
                    if suffix_len <= 0:
                        self.send_error(HTTPStatus.REQUESTED_RANGE_NOT_SATISFIABLE)
                        file_obj.close()
                        return None
                    start = max(file_len - suffix_len, 0)
                else:
                    start = int(start_raw)

                if end_raw:
                    end = int(end_raw)

                if start >= file_len or end < start:
                    self.send_response(HTTPStatus.REQUESTED_RANGE_NOT_SATISFIABLE)
                    self.send_header("Content-Range", f"bytes */{file_len}")
                    self.send_header("Content-Length", "0")
                    self.end_headers()
                    file_obj.close()
                    return None

                end = min(end, file_len - 1)
                content_length = end - start + 1
                self.send_response(HTTPStatus.PARTIAL_CONTENT)
                self.send_header("Content-Type", ctype)
                self.send_header("Accept-Ranges", "bytes")
                self.send_header("Content-Range", f"bytes {start}-{end}/{file_len}")
                self.send_header("Content-Length", str(content_length))
                self.send_header("Last-Modified", self.date_time_string(fs.st_mtime))
                self.send_header("Cache-Control", "no-cache")
                self.end_headers()
                file_obj.seek(start)
                self.range = (start, end)
                return file_obj

            self.send_response(HTTPStatus.OK)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(file_len))
            self.send_header("Last-Modified", self.date_time_string(fs.st_mtime))
            self.send_header("Accept-Ranges", "bytes")
            self.send_header("Cache-Control", "no-cache")
            self.end_headers()
            self.range = None
            return file_obj
        except Exception:
            file_obj.close()
            raise

    def copyfile(self, source, outputfile):
        byte_range = getattr(self, "range", None)
        if not byte_range:
            shutil.copyfileobj(source, outputfile)
            return

        start, end = byte_range
        remaining = end - start + 1
        bufsize = 64 * 1024
        while remaining > 0:
            chunk = source.read(min(bufsize, remaining))
            if not chunk:
                break
            outputfile.write(chunk)
            remaining -= len(chunk)

    def list_directory(self, path):
        try:
            entries = sorted(os.listdir(path), key=lambda name: name.lower())
        except OSError:
            self.send_error(HTTPStatus.NOT_FOUND, "No permission to list directory")
            return None

        display_path = html.escape(urllib.parse.unquote(self.path), quote=False)
        encoded = [
            "<!doctype html>",
            "<html><head>",
            '<meta charset="utf-8">',
            f"<title>Directory listing for {display_path}</title>",
            "</head><body>",
            f"<h1>Directory listing for {display_path}</h1>",
            "<hr><ul>",
        ]
        for name in entries:
            full_path = os.path.join(path, name)
            display_name = link_name = name
            if os.path.isdir(full_path):
                display_name = link_name = name + "/"
            if os.path.islink(full_path):
                display_name = name + "@"
            encoded.append(
                f'<li><a href="{urllib.parse.quote(link_name)}">{html.escape(display_name, quote=False)}</a></li>'
            )
        encoded.extend(["</ul><hr></body></html>"])
        body = "\n".join(encoded).encode("utf-8", "surrogateescape")

        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
        return None

    def translate_path(self, path):
        path = path.split("?", 1)[0].split("#", 1)[0]
        path = posixpath.normpath(urllib.parse.unquote(path))
        parts = [part for part in path.split("/") if part and part not in (".", "..")]
        resolved = os.getcwd()
        for part in parts:
            resolved = os.path.join(resolved, part)
        return resolved


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8001
    server = ThreadingHTTPServer(("127.0.0.1", port), RangeRequestHandler)
    print(f"Serving with range support on http://127.0.0.1:{port}")
    server.serve_forever()


if __name__ == "__main__":
    main()
