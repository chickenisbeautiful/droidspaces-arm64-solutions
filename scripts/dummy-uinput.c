#include <linux/uinput.h>
#include <linux/input.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>
#include <stdio.h>
#include <errno.h>
#include <sys/ioctl.h>

#define CHK(x) do { if ((x) < 0) fprintf(stderr, "%s: %s\n", #x, strerror(errno)); } while (0)

static void abs_setup(int fd, int code, int min, int max) {
    struct uinput_abs_setup a;
    memset(&a, 0, sizeof(a));
    a.code = code;
    a.absinfo.minimum = min;
    a.absinfo.maximum = max;
    CHK(ioctl(fd, UI_ABS_SETUP, &a));
}

int main(void) {
    int fd = open("/dev/uinput", O_WRONLY | O_NONBLOCK);
    if (fd < 0) { perror("open /dev/uinput"); return 1; }

    CHK(ioctl(fd, UI_SET_EVBIT, EV_KEY));
    CHK(ioctl(fd, UI_SET_KEYBIT, BTN_SOUTH));
    CHK(ioctl(fd, UI_SET_KEYBIT, BTN_EAST));
    CHK(ioctl(fd, UI_SET_KEYBIT, BTN_NORTH));
    CHK(ioctl(fd, UI_SET_KEYBIT, BTN_WEST));
    CHK(ioctl(fd, UI_SET_KEYBIT, BTN_TL));
    CHK(ioctl(fd, UI_SET_KEYBIT, BTN_TR));
    CHK(ioctl(fd, UI_SET_KEYBIT, BTN_START));
    CHK(ioctl(fd, UI_SET_KEYBIT, BTN_SELECT));
    CHK(ioctl(fd, UI_SET_KEYBIT, BTN_MODE));

    CHK(ioctl(fd, UI_SET_EVBIT, EV_ABS));
    CHK(ioctl(fd, UI_SET_ABSBIT, ABS_X));
    CHK(ioctl(fd, UI_SET_ABSBIT, ABS_Y));
    CHK(ioctl(fd, UI_SET_ABSBIT, ABS_RX));
    CHK(ioctl(fd, UI_SET_ABSBIT, ABS_RY));
    CHK(ioctl(fd, UI_SET_ABSBIT, ABS_HAT0X));
    CHK(ioctl(fd, UI_SET_ABSBIT, ABS_HAT0Y));

    abs_setup(fd, ABS_X, -32768, 32767);
    abs_setup(fd, ABS_Y, -32768, 32767);
    abs_setup(fd, ABS_RX, -32768, 32767);
    abs_setup(fd, ABS_RY, -32768, 32767);
    abs_setup(fd, ABS_HAT0X, -1, 1);
    abs_setup(fd, ABS_HAT0Y, -1, 1);

    struct uinput_setup setup;
    memset(&setup, 0, sizeof(setup));
    snprintf(setup.name, UINPUT_MAX_NAME_SIZE, "Dummy Gamepad");
    setup.id.bustype = BUS_USB;
    setup.id.vendor = 0x045e;
    setup.id.product = 0x02fd;
    setup.id.version = 1;
    CHK(ioctl(fd, UI_DEV_SETUP, &setup));
    CHK(ioctl(fd, UI_DEV_CREATE));
    fprintf(stderr, "dummy created\n");

    sleep(30);

    CHK(ioctl(fd, UI_DEV_DESTROY));
    close(fd);
    return 0;
}
