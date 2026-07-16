#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static volatile sig_atomic_t running = 1;
static void stop_running(int sig) { (void)sig; running = 0; }

static void add_ns(struct timespec *t, long ns)
{
    t->tv_nsec += ns;
    while (t->tv_nsec >= 1000000000L) {
        t->tv_nsec -= 1000000000L;
        ++t->tv_sec;
    }
}

int main(int argc, char **argv)
{
    const char *pan = "/sys/class/graphics/fb0/pan";
    long hz = argc > 1 ? strtol(argv[1], NULL, 10) : 60;
    if (hz < 1 || hz > 120) {
        fprintf(stderr, "s8-frame-pump: invalid refresh rate %ld\n", hz);
        return 2;
    }
    int fd = open(pan, O_WRONLY | O_CLOEXEC);
    if (fd < 0) {
        fprintf(stderr, "s8-frame-pump: open %s: %s\n", pan, strerror(errno));
        return 1;
    }
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = stop_running;
    sigemptyset(&sa.sa_mask);
    sigaction(SIGTERM, &sa, NULL);
    sigaction(SIGINT, &sa, NULL);

    const char command[] = "0,0\n";
    const long period_ns = 1000000000L / hz;
    struct timespec next;
    clock_gettime(CLOCK_MONOTONIC, &next);

    while (running) {
        if (lseek(fd, 0, SEEK_SET) < 0 || write(fd, command, sizeof(command) - 1) != (ssize_t)(sizeof(command) - 1)) {
            fprintf(stderr, "s8-frame-pump: pan write: %s\n", strerror(errno));
            close(fd);
            return 1;
        }
        add_ns(&next, period_ns);
        while (clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, &next, NULL) == EINTR && running) {}
    }
    close(fd);
    return 0;
}
