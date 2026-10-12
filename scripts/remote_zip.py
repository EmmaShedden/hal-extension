"""Read members of a remote zip via HTTP range requests (avoids downloading 113 GB of traces)."""
import io, urllib.request, zipfile

BASE = "https://huggingface.co/datasets/agent-evals/hal_traces/resolve/main/"


class HTTPRangeFile(io.RawIOBase):
    def __init__(self, url):
        self.url = url
        req = urllib.request.Request(url, method="HEAD")
        with urllib.request.urlopen(req) as r:
            self.size = int(r.headers["Content-Length"])
            self.url = r.url  # follow redirect to CDN
        self.pos = 0

    def seekable(self):
        return True

    def readable(self):
        return True

    def tell(self):
        return self.pos

    def seek(self, off, whence=0):
        self.pos = {0: off, 1: self.pos + off, 2: self.size + off}[whence]
        return self.pos

    def read(self, n=-1):
        if n is None or n < 0:
            n = self.size - self.pos
        if n == 0 or self.pos >= self.size:
            return b""
        end = min(self.pos + n, self.size) - 1
        req = urllib.request.Request(self.url, headers={"Range": f"bytes={self.pos}-{end}"})
        with urllib.request.urlopen(req) as r:
            data = r.read()
        self.pos += len(data)
        return data

    def readinto(self, b):
        data = self.read(len(b))
        b[: len(data)] = data
        return len(data)


def open_remote_zip(name):
    f = io.BufferedReader(HTTPRangeFile(BASE + name), buffer_size=1 << 20)
    return zipfile.ZipFile(f)
