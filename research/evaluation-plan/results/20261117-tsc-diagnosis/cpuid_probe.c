#include <cpuid.h>
#include <stdio.h>

int main(void)
{
    unsigned int a, b, c, d;

    if (!__get_cpuid_count(7, 0, &a, &b, &c, &d))
        return 1;
    printf("CPUID.7.0.EBX=0x%08x TSC_ADJUST=%u\n", b, (b >> 1) & 1);
    if (!__get_cpuid(0x80000007, &a, &b, &c, &d))
        return 1;
    printf("CPUID.80000007.EDX=0x%08x invariant_TSC=%u\n", d, (d >> 8) & 1);
    return 0;
}
