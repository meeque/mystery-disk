# How did my ext3 superblocks get so messed up? And how to fix them?



I've recently found an old external hard disk and I have no idea what's on it. There was only one partition, encrypted with dm-crypt. Luckily I still remembered some of the passphrases that I used back in the day, and one of them actually worked. Using the right passphrase I got this:

```
$ sudo cryptsetup open --type plain /dev/sda1 mystery-disk
[...]
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



The Problem
-----------

Unfortunately, I couldn't mount the **ext3 filesystem**:

```
$ sudo mount --read-only --types ext3 /dev/mapper/mystery-disk /mnt/mystery-disk/
mount: /mnt/mystery-disk: wrong fs type, bad option, bad superblock on /dev/mapper/mystery-disk, missing codepage or helper program, or other error.
```
Same when I omitted the `--types` option. A quick `fsck` run did not help either.



Rescue Image
------------

At this point I decided to pull an image before any more fixing attempts. I've tried both `dd` and `ddrescue` several times and none of them gave me any errors. So I think the **disk itself is fine**:

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



Let's Check
-----------

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



Superblocks
-----------

So apparently the superblock was messed up. But I had no idea how to find an alternative one. Eventually I stumbled across this other question here, about [recovering ext4 superblocks](https://unix.stackexchange.com/questions/33284/recovering-ext4-superblocks). (And I think that most of this applies to my ext3, too.)

I tried the trick with `mke2fs -n`, but I was uncertain which blocksize my ext3 fs might have used. So I tried the usual suspects: `1024`, `2048`, `4096`. This is what I got for `4096`, which turned out to be the correct one:

```
$ mke2fs -n -b 4096 mystery-disk.img 
[...]
Superblock backups stored on blocks: 
	32768, 98304, 163840, 229376, 294912, 819200, 884736, 1605632, 2654208, 
	4096000, 7962624, 11239424
```

I then tried to pass all of these to `e2fsck`, with or without specifying a block-size. But it always complained about corruption in superblock. Outputs where pretty much the same as when using the default superblock.

And I had no idea, if `mke2fs -n` had even produced useful results. Some other sources said that it only works, if called with the same parameters as when the fs was formatted. But I had no idea what parameters I had used over a decade ago. I couldn't even be sure that the `mke2fs` from back then would be compatible with the one that I use today.



More Superblocks?
-----------------

So I searched the web for other methods for finding ext3 superblocks. I found surprisingly little, but eventually I stumbled across some technical documentation of ext4 superblock datastructures in the Linux kernel [docs](https://www.kernel.org/doc/html/latest/filesystems/ext4/globals.html) and [wiki](https://ext4.wiki.kernel.org/index.php/Ext4_Disk_Layout#The_Super_Block).

These mentioned magic bytes and some enumerated values, so I came up with a regexp based on the superblock fields `s_magic`, `s_state`, and `s_errors`:

```
$ LANG=C grep --only-matching --byte-offset --binary --text --perl-regexp '\x53\xEF[\x00-\x07]\x00[\x01-\x03]\x00' mystery-disk.img
```

This gave me a reasonable number of hits. So I wrote [a script](https://github.com/meeque/mystery-disk/blob/master/find-super.sh) around it, to calculate and print superblock numbers, sizes, etc. Some of the hits were clearly false positives, e.g. because they indicate unlikely block sizes. But the script also confirmed all the superblocks that I got with the `mke2fs -n` method earlier. 

Here's an excerpt of the [script outputs](https://github.com/meeque/mystery-disk/blob/master/out/mystery-disk.find-super.log):

```
$ ./find-super.sh mystery-disk.img
[...]

Scan for superblocks complete. Found 21 candidate superblocks.
Printing superblock meta data...

Processing candidate superblock with magic bytes at 1080...
Superblock offset:     1024   (at 1024 in block 0)
Block size:            4096   (2**(10+2))
Filesystem size:       11525729222656 bytes   (2813898736 blocks, ~10734 GiB)

Processing candidate superblock with magic bytes at 26870840...
Superblock offset:     26870784   (at 1024 in block 6560)
Block size:            4096   (2**(10+2))
Filesystem size:       2889757667328 bytes   (705507243 blocks, ~2691 GiB)

[...]

Processing candidate superblock with magic bytes at 134217784...
Superblock offset:     134217728   (at 0 in block 32768)
Block size:            4096   (2**(10+2))
Filesystem size:       6483460464640 bytes   (1582876090 blocks, ~6038 GiB)

[...]

Processing candidate superblock with magic bytes at 37909356558...
Superblock offset:     37909356502   (at 982 in block 37020855)
Block size:            1024   (2**(10+0))
Filesystem size:       0 bytes   (0 blocks, ~0 GiB)

Processing candidate superblock with magic bytes at 46036680760...
Superblock offset:     46036680704   (at 0 in block 11239424)
Block size:            4096   (2**(10+2))
Filesystem size:       10750096064512 bytes   (2624535172 blocks, ~10011 GiB)
```

I've hex-dumped some of them and at a first glance they look plausible.

However, still no luck with `e2fsck`. I've also tried `dumpe2fs` with all possible superblocks, e.g. like this:

```
$ dumpe2fs -o superblock=32768 -o blocksize=4096 mystery-disk.img
dumpe2fs 1.45.5 (07-Jan-2020)
dumpe2fs: The ext2 superblock is corrupt while trying to open mystery-disk.img
Couldn't find valid filesystem superblock.
```

It always says "superblock is corrupt", but it never says why. I assume that some enum fields have unsupported values or the checksum (in field `s_checksum` at the end of each superblock) does not match. I've tried to calculate and compare the checksums myself, using advice from [this question](https://unix.stackexchange.com/questions/506714/ext4-crc32c-checksum-algorithms-are-badly-documented). But so far I didn't get the calculations right, as confirmed by testing against a working ext4 filesystem. 

What puzzles me, is that each of these superblocks indicates a **different filesystem size** (as calculated from the `s_blocks_count_lo` and `s_log_block_size` fields). Ignoring outliers like 0, alleged fs sizes range from **~712 GiB** to **~15957 GiB**. But my disk image is only **77G** and the physical disk wasn't much larger. (There was the partition table and some padding at the end, but the whole rest of the disk was occupied by this dm-crypt encrypted ext3 filesystem.)

Is there any chance to figure out which of the superblock might be suited best for new attempts to fix the filesystem? If so, what next steps would be recommended?

