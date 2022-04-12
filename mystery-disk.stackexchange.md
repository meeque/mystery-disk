How did my ext3 superblocks get so messed up? And how to fix them?



I've recently found an old external hard disk and I have no idea whats on it. There was only one partition on it, encrypted with dm-crypt. Luckily I still remembered some of the passphrases that I used back in the day, and one of them actually worked. Using the right passphrase I got this:

```
$ sudo cryptsetup open --type plain /dev/sda1 mystery-disk
$ sudo blkid /dev/mapper/mystery-disk
/dev/mapper/mystery-disk: UUID="6592b48b-7763-4c07-8d57-c5c6d827a895" SEC_TYPE="ext2" TYPE="ext3"
$ sudo file -sL /dev/mapper/mystery-disk
/dev/mapper/mystery-disk: Linux rev 1.0 ext3 filesystem data, UUID=6592b48b-7763-4c07-8d57-c5c6d827a895
$ sudo lsblk -f /dev/sda
NAME             FSTYPE LABEL UUID                                 FSAVAIL FSUSE% MOUNTPOINT
sda                                                                               
└─sda1                                                                            
  └─mystery-disk ext3         6592b48b-7763-4c07-8d57-c5c6d827a895
```

Unfortunately, I couldn't mount this ext3 filesystem:

```
$ sudo mount --read-only --types ext3 /dev/mapper/mystery-disk /mnt/mystery-disk/
mount: /mnt/mystery-disk: wrong fs type, bad option, bad superblock on /dev/mapper/mystery-disk, missing codepage or helper program, or other error.
```
Same when I omitted the `--types` option. A quick `fsck` run did not help either.



At this point I decided to pull an image before any more fixing attempts. I've tried both `dd` and `ddrescue` several times (deleting the image in between) and none of them gave me any errors. So I think the disk itself is fine:

```
$ sudo dd if=/dev/mapper/mystery-disk bs=4096 > mystery-disk.img
20103331+1 records in
20103331+1 records out
82343245824 bytes (82 GB, 77 GiB) copied, 2672.71 s, 30.8 MB/s
```

```
$ sudo ddrescue -r 3 /dev/mapper/mystery-disk mystery-disk.img mystery-disk.ddrescue.log
GNU ddrescue 1.23
Press Ctrl-C to interrupt
     ipos:   82343 MB, non-trimmed:        0 B,  current rate:  12007 kB/s
     opos:   82343 MB, non-scraped:        0 B,  average rate:  31392 kB/s
non-tried:        0 B,  bad-sector:        0 B,    error rate:       0 B/s
  rescued:   82343 MB,   bad areas:        0,        run time:     43m 42s
pct rescued:  100.00%, read errors:        0,  remaining time:         n/a
                              time since last successful read:         n/a
Finished
```

With the image, I tried a couple more runs of fsck, but it didn't get me anywhere:

```
$ e2fsck mystery-disk.img
e2fsck 1.45.5 (07-Jan-2020)
ext2fs_open2: The ext2 superblock is corrupt
e2fsck: Superblock invalid, trying backup blocks...
e2fsck: The ext2 superblock is corrupt while trying to open mystery-disk.img
e2fsck: Trying to load superblock despite errors...
ext2fs_check_desc: Corrupt group descriptor: bad block for block bitmap
e2fsck: Group descriptors look bad... trying backup blocks...
Error reading block 1198463829 (Attempt to read block from filesystem resulted in short read).  Ignore error<y>? yes
Force rewrite<y>? yes
Superblock has an invalid journal (inode 8).
Clear<y>? yes
*** journal has been deleted ***

Corruption found in superblock.  (r_blocks_count = 3755560972).

The superblock could not be read or does not describe a valid ext2/ext3/ext4
filesystem.  If the device is valid and it really contains an ext2/ext3/ext4
filesystem (and not swap or ufs or something else), then the superblock
is corrupt, and you might try running e2fsck with an alternate superblock:
    e2fsck -b 8193 <device>
 or
    e2fsck -b 32768 <device>


mystery-disk.img: ***** FILE SYSTEM WAS MODIFIED *****
$
$
$ e2fsck mystery-disk.img
e2fsck 1.45.5 (07-Jan-2020)
ext2fs_open2: The ext2 superblock is corrupt
e2fsck: Superblock invalid, trying backup blocks...
e2fsck: The ext2 superblock is corrupt while trying to open mystery-disk.img
e2fsck: Trying to load superblock despite errors...
ext2fs_check_desc: Corrupt group descriptor: bad block for block bitmap
e2fsck: Group descriptors look bad... trying backup blocks...
Superblock has an invalid journal (inode 8).
Clear<y>? yes
*** journal has been deleted ***

Corruption found in superblock.  (r_blocks_count = 3755560972).

The superblock could not be read or does not describe a valid ext2/ext3/ext4
filesystem.  If the device is valid and it really contains an ext2/ext3/ext4
filesystem (and not swap or ufs or something else), then the superblock
is corrupt, and you might try running e2fsck with an alternate superblock:
    e2fsck -b 8193 <device>
 or
    e2fsck -b 32768 <device>


mystery-disk.img: ***** FILE SYSTEM WAS MODIFIED *****
```

So apparently the superblock was messed up. But I had no idea how to find an alternative one. I started researching some more and eventually I stumbled across this other question here, about [recovering ext4 superblocks](https://unix.stackexchange.com/questions/33284/recovering-ext4-superblocks). (And I believe that ext2/3/4 are similar enough in these low-level datastructures, so that most of that applies to my ext3, too.)


