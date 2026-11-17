#include <linux/io_uring.h>
#include <sys/syscall.h>
#include <unistd.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
int main(){ unsigned sizes[]={1,8,128,1024,4096,32768};
for(int i=0;i<6;i++){struct io_uring_params p; memset(&p,0,sizeof p);
int fd=syscall(__NR_io_uring_setup,sizes[i],&p);
printf("entries %u -> %d %s\n",sizes[i],fd,fd<0?strerror(errno):"ok"); if(fd>=0) close(fd);}
}
