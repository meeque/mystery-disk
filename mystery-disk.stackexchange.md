How did my ext3 superblocks get so messed up? And how to fix them?
==================================================================



I've recently found an old external hard disk and I have no idea what's on it. There was only one partition, encrypted with [dm-crypt](https://www.kernel.org/doc/html/latest/admin-guide/device-mapper/dm-crypt.html). Luckily I still remembered some of the passphrases that I used back in the day and one of them actually worked.
With the right passphrase, cryptsetup revealed an **ext3 filesystem** inside. Unfortunately, I couldn't mount it:

```
$ sudo mount --read-only --types ext3 /dev/mapper/mystery-disk /mnt/mystery-disk/
mount: /mnt/mystery-disk: wrong fs type, bad option, bad superblock on /dev/mapper/mystery-disk, missing codepage or helper program, or other error.
```

Same when I omitted the `--types` option. A quick `fsck` run did not help either.



Let's Image, Check, Dump
------------------------

At this point I decided to pull an image before any more fixing attempts. I've tried both `dd` and `ddrescue` several times and neither [gave me](https://github.com/meeque/mystery-disk/blob/master/out/mystery-disk.dd.log) [any errors](https://github.com/meeque/mystery-disk/blob/master/out/mystery-disk.ddrescue.log). So I think the **disk itself is fine**:

With the image, I tried a couple more runs of `e2fsck`, but it didn't get me anywhere:

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
```

```
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

The `dumpe2fs` tool didn't help either. Just complained about corrupt superblock, but didn't say why it's corrupt:

```
$ dumpe2fs -o superblock=32768 -o blocksize=4096 mystery-disk.img
dumpe2fs 1.45.5 (07-Jan-2020)
dumpe2fs: The ext2 superblock is corrupt while trying to open mystery-disk.img
Couldn't find valid filesystem superblock.
```



Superblocks
-----------

So apparently the superblock was messed up. But I had no idea how to find an alternative one. Eventually I stumbled across this other question here, about [recovering ext4 superblocks](https://unix.stackexchange.com/questions/33284/recovering-ext4-superblocks). (And I think that most of this applies to my ext3, too.)

I tried the trick with `mke2fs -n`, but I was uncertain which blocksize my ext3 fs might have used. So I tried the usual suspects: `1024`, `2048`, `4096`. This is what I got for `4096`, which later turned out to be the correct one:

```
$ mke2fs -n -b 4096 mystery-disk.img 
[...]
Superblock backups stored on blocks: 
	32768, 98304, 163840, 229376, 294912, 819200, 884736, 1605632, 2654208, 
	4096000, 7962624, 11239424
```

I then tried to pass all of these to `e2fsck`, with or without specifying a block-size. But it always complained about corruption in superblock. Outputs where pretty much the same as when using the default superblock.

And I had no idea, if `mke2fs -n` had even produced useful results. Some other sources said that it only works, if called with the same parameters as when the filesystem was created. But what parameters could I have used over a decade ago? I'm not even sure that the `mke2fs` from back then would be compatible with the one that I use today.



More Superblocks?
-----------------

I searched the web for other methods for finding ext3 superblocks. I found surprisingly little, but eventually I stumbled across some technical documentation of ext4 superblock data-structures in the [Linux kernel docs](https://www.kernel.org/doc/html/latest/filesystems/ext4/globals.html).

These mentioned magic bytes and some enumerated values, so I came up with a regexp based on the superblock fields `s_magic`, `s_state`, and `s_errors`:

```
$ LANG=C grep --only-matching --byte-offset --binary --text --perl-regexp '\x53\xEF[\x00-\x07]\x00[\x01-\x03]\x00' mystery-disk.img
```

This gave me a reasonable number of hits. So I wrote [a script](https://github.com/meeque/mystery-disk/blob/master/find-super.sh) around it, to calculate and print superblock numbers, sizes, etc. Some of the hits were clearly false positives, e.g. because they indicated unlikely block sizes or offsets. But the script also confirmed all the superblocks that I had found with `mke2fs -n` earlier.

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

Still no luck with `e2fsck` or `dumpe2fs` with any of these superblocks. They always say "superblock is corrupt", but never say why.

So I've hex-dumped some of the superblocks, see [here](https://github.com/meeque/mystery-disk/blob/master/out/mystery-disk.hexdump-superblock-0.log) and [here](https://github.com/meeque/mystery-disk/blob/master/out/mystery-disk.hexdump-superblock-32768.log). Not sure, if they are plausible. They are a little heavy on the zeros. In particular, all the **checksums are zero** (see field `s_checksum` at the end of each superblock).

What puzzles me most, is that each of these superblocks indicates a **different filesystem size** (as calculated from the `s_blocks_count_lo` and `s_log_block_size` fields). Ignoring outliers like 0, alleged sizes range from **~712 GiB** to **~15957 GiB**. But my disk image is only **77G**, same as the external hard disk.

Is there any chance to figure out **which of the superblocks** might be suited best for further rescue attempts?  
If so, what would be the **next steps?**
Any **other ideas?**  
Am I missing **something trivial**?  

