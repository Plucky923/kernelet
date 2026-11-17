| measurement | boots | median (cycles) | p99 median | p99 worst | median (ns) | p99 worst (ns) |
|---|---:|---:|---:|---:|---:|---:|
| first touch of a mapped page (per page) | 5 | 64 | 96 | 480 | 20 | 150 |
| map, one page per call (per call) | 5 | 447 | 479 | 1184 | 140 | 371 |
| map, 512 pages under one cursor (per page) | 5 | 472 | 605 | 1701 | 148 | 533 |
| protect 2 MiB read-only + flush (per 512 pages) | 5 | 243808 | 289632 | 522848 | 76,328 | 163,686 |
| read after protect (per page) | 5 | 64 | 64 | 128 | 20 | 40 |
| copy 64 B out of tenant memory | 5 | 128 | 160 | 640 | 40 | 200 |
| copy 4 KiB out of tenant memory | 5 | 3520 | 3616 | 7744 | 1,102 | 2,424 |
| fork, 64 MiB mapped | 5 | 25069413 | 25580564 | 45221835 | 7,848,378 | 14,157,413 |
| the child reads all 64 MiB | 5 | 1786240 | 1817152 | 2326848 | 559,211 | 728,457 |
| fork + the child's reads | 5 | 26816901 | 27397716 | 47548683 | 8,395,456 | 14,885,870 |
| the parent re-reads all 64 MiB after fork | 5 | 1777952 | 1854944 | 2362048 | 556,616 | 739,477 |
| munmap of the 64 MiB | 5 | 872480 | 1049690 | 1672640 | 273,144 | 523,646 |
