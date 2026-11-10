/*
 * s8-frame-pump: commit the fb0 pan at a fixed rate.
 *
 * Samsung's DECON driver on the Galaxy S8 shows only one committed frame of
 * the command-mode AMOLED panel; X11 keeps rendering but nothing reaches the
 * glass until the next pan commit. Writing "0,0" to the pan attribute at the
 * panel refresh rate keeps it presenting.
 *
 *   s8-frame-pump [hz] [pan-path]      (defaults: 60 /sys/class/graphics/fb0/pan)
 */
#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#define DEFAULT_PAN "/sys/class/graphics/fb0/pan"
#define NS_PER_SEC 1000000000L

static volatile sig_atomic_t running = 1;
static void stop_running(int sig) { (void)sig; running = 0; }

static void add_ns(struct timespec *t, long ns)
{
    t->tv_nsec += ns;
    while (t->tv_nsec >= NS_PER_SEC) {
        t->tv_nsec -= NS_PER_SEC;
        ++t->tv_sec;
    }
}

static long diff_ns(const struct timespec *a, const struct timespec *b)
{
    return (a->tv_sec - b->tv_sec) * NS_PER_SEC + (a->tv_nsec - b->tv_nsec);
}

static int usage(FILE *out)
{
    fprintf(out, "usage: s8-frame-pump [hz] [pan-path]\n"
                 "  hz        refresh rate, 1-120 (default 60)\n"
                 "  pan-path  sysfs pan attribute (default " DEFAULT_PAN ")\n");
    return out == stdout ? 0 : 2;
}

int main(int argc, char **argv)
{
    const char *pan = DEFAULT_PAN;
    long hz = 60;

    if (argc > 3)
        return usage(stderr);
    if (argc > 1) {
        char *end;
        if (!strcmp(argv[1], "-h") || !strcmp(argv[1], "--help"))
            return usage(stdout);
        errno = 0;
        hz = strtol(argv[1], &end, 10);
        if (errno || *end != '\0' || end == argv[1] || hz < 1 || hz > 120) {
            fprintf(stderr, "s8-frame-pump: invalid refresh rate '%s'\n", argv[1]);
            return 2;
        }
    }
    if (argc > 2)
        pan = argv[2];

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
    sigaction(SIGHUP, &sa, NULL);

    const char command[] = "0,0\n";
    const long period_ns = NS_PER_SEC / hz;
    struct timespec next;
    clock_gettime(CLOCK_MONOTONIC, &next);

    while (running) {
        if (lseek(fd, 0, SEEK_SET) < 0 || write(fd, command, sizeof(command) - 1) != (ssize_t)(sizeof(command) - 1)) {
            fprintf(stderr, "s8-frame-pump: pan write: %s\n", strerror(errno));
            close(fd);
            return 1;
        }
        add_ns(&next, period_ns);

        /* After suspend (or a long stall) CLOCK_MONOTONIC may be far ahead of
         * the schedule; resynchronise instead of replaying every missed tick
         * as a burst of commits. */
        struct timespec now;
        clock_gettime(CLOCK_MONOTONIC, &now);
        if (diff_ns(&now, &next) > period_ns)
            next = now;

        while (clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, &next, NULL) == EINTR && running) {}
    }
    close(fd);
    return 0;
}
