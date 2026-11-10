#!/usr/bin/env python3
import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest


class BufferCleanupTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        patch = (Path(__file__).resolve().parents[1] /
                 "patches/libhybris-android9-musl-x11.patch").read_text()
        section = patch.split("diff --git a/hybris/egl/platforms/x11/x11_window.cpp ", 1)[1]
        section = section.split("\ndiff --git ", 1)[0]
        source = "\n".join(line[1:] for line in section.splitlines()
                           if line.startswith("+") and not line.startswith("+++"))
        start = source.index("void X11NativeWindow::destroyBuffers()")
        method = source[start:source.index("\n}", start) + 2]
        cls.temp = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls.temp.cleanup)
        directory = Path(cls.temp.name)
        harness = directory / "cleanup.cpp"
        harness.write_text(r'''
#include <cstdlib>
#include <deque>
#include <iostream>
#include <list>
#include <vector>
#define TRACE(...) ((void)0)
struct X11NativeWindowBuffer { int releases = 0; };
struct X11NativeWindow {
    std::list<X11NativeWindowBuffer*> m_bufList;
    std::deque<X11NativeWindowBuffer*> queue;
    X11NativeWindowBuffer *m_lastBuffer = NULL;
    int m_freeBufs = 0;
    void destroyBuffer(X11NativeWindowBuffer *buffer) {
        ++buffer->releases;
        --m_freeBufs;
    }
    void destroyBuffers();
};
''' + method + r'''
int main(int argc, char **argv) {
    if (argc != 2) return 2;
    std::vector<X11NativeWindowBuffer> buffers(std::atoi(argv[1]));
    X11NativeWindow window;
    for (auto &buffer : buffers) window.m_bufList.push_back(&buffer);
    if (!buffers.empty()) {
        window.queue.push_back(&buffers.front());
        window.m_lastBuffer = &buffers.back();
    }
    window.m_freeBufs = buffers.size();
    window.destroyBuffers();
    if (!window.m_bufList.empty() || window.m_freeBufs != 0) return 1;
    if (!window.queue.empty() || window.m_lastBuffer != NULL) {
        std::cerr << "stale buffer references survived destroyBuffers()\n";
        return 1;
    }
    for (const auto &buffer : buffers) {
        if (buffer.releases != 1) {
            std::cerr << "buffer released " << buffer.releases << " times, expected 1\n";
            return 1;
        }
    }
    return 0;
}
''')
        cls.binary = directory / "cleanup"
        subprocess.run(shlex.split(os.environ.get("CXX", "c++")) + [
            "-std=c++11", "-Wall", "-Wextra", "-Werror", "-D_GLIBCXX_DEBUG",
            str(harness), "-o", str(cls.binary)], check=True)

    def test_every_buffer_is_released_once(self):
        for count in (0, 1, 2, 3, 4):
            with self.subTest(buffer_count=count):
                result = subprocess.run([str(self.binary), str(count)],
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
