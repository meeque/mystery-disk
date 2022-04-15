#!/bin/bash
set -eo pipefail



# For documentation of ext2/3/4 superblock datastructures, see:
# https://www.kernel.org/doc/html/latest/filesystems/ext4/globals.html#super-block
# https://ext4.wiki.kernel.org/index.php/Ext4_Disk_Layout

superblock_pattern='\x53\xEF[\x00-\x07]\x00[\x01-\x03]\x00'



arguments=$(getopt --options 'dc' --longoptions 'dumpe2fs,checksum' -n 'find-super.sh' -- "$@")
eval set -- "${arguments}"

while true
do
    case "$1" in
        -d|--dumpe2fs)
            do_dumpe2fs=1
            ;;
        -c|--checksum)
            do_checksum=1
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "Unknown option argument $1. Ignoring."
            ;;
    esac
    shift
done

if [[ -n "$1" ]]
then
    fs_file="$1"
    echo "Preparing to scan filesystem in ${fs_file} for ext2/3/4 superblocks."
    echo
else
    echo "Fatal: Non-option argument missing. Please specify the name of a block device or image file that contains an ext2/3/4 filesystem."
    exit
fi

if [[ -v "$2" ]]
then
    magic_file="$2"
else
    magic_file="$( basename "${fs_file}" | sed -e 's/[.].*$//' ).ext3-magic-bytes-offsets.txt"
    echo "Info: Second argument missing. Deriving magic bytes offsets cache file name from filesystem file name:"
    echo "${magic_file}"
    echo "To use custom magic bytes offsets cache file, rerun and specify file name as second argument."
    echo
fi



if [[ ! -f "${magic_file}" ]]
then
    echo "Trying to find candidate supeblocks of ext2/3/4 filesystem..."
    echo "Scanning filesystem for ext2/3/4 magic bytes and related patterns..."
    echo "Caching magic byte offsets in file ${magic_file}..."

    LANG=C grep --only-matching --byte-offset --binary --text --perl-regexp "${superblock_pattern}" "${fs_file}" \
        | grep --binary --text --only-matching --extended-regexp '^[0-9]+' \
        > "${magic_file}"
    echo "done."
else
    echo "Omitting scan for magic bytes. Using cached offsets from file ${magic_file} instead."
    echo "To trigger a new scan for magic bytes, delete the file and rerun!"
fi
magic_offsets="$( cat "${magic_file}" )"
magic_offsets_count="$( echo ${magic_offsets} | wc --words )"



echo
echo "Scan for superblocks complete. Found ${magic_offsets_count} candidate superblocks."
echo "Printing superblock meta data..."

for magic_offset in ${magic_offsets}
do
    echo
    echo "Processing candidate superblock with magic bytes at ${magic_offset}..."
    superblock_offset="$(( magic_offset - 0x38 ))"

    log_block_size_offset="$(( superblock_offset + 0x18 ))"
    log_block_size="$( od --address-radix=n --skip-bytes="${log_block_size_offset}" --read-bytes=4 --format=u4 --endian=little "${fs_file}" | xargs )"
    if (( log_block_size > 22 ))
    then
        echo "Error: Very large block-size exponent ${log_block_size} found. No way this is a valid superblock. Skipping."
    else
        block_size="$(( 2 ** ( 10 + log_block_size ) ))"
        superblock_block="$(( superblock_offset / block_size ))"
        superblock_block_offset="$(( superblock_offset % block_size ))"

        blocks_count_offset="$(( superblock_offset + 0x04 ))"
        blocks_count="$( od --address-radix=n --skip-bytes="${blocks_count_offset}" --read-bytes=4 --format=u4 --endian=little "${fs_file}" | xargs )"
        fs_size="$(( blocks_count * block_size ))"

        echo "Superblock offset:     ${superblock_offset}   (at ${superblock_block_offset} in block ${superblock_block})"
        echo "Block size:            ${block_size}   (2**(10+${log_block_size}))"
        echo "Filesystem size:       ${fs_size} bytes   (${blocks_count} blocks, ~$(( fs_size / (1024**3) )) GiB)"

        if [[ "${do_checksum}" ]]
        then
            checksum_offset="$(( superblock_offset + 0x03FC ))"
            checksum_stored="$( od --address-radix=n --skip-bytes="${checksum_offset}" --read-bytes=4 --format=x4 --endian=little "${fs_file}" | xargs )"
            checksum_calculated="$( crc32 <( dd if="${fs_file}" skip="${superblock_offset}" bs=1 count="$((0x03FC))" status=none ) )"
            checksum_calculated="$( bc <<<"ibase=G; obase=G; FFFFFFFF - ${checksum_calculated^^}" | sed -e 's/\s//g' )"
            echo "Superblock checksum:   0x${checksum_stored^^} / 0x${checksum_calculated}   (stored / calculated)"
        fi

        if [[ "${do_dumpe2fs}" ]]
        then
            (
                echo
                set -x +e
                dumpe2fs -o superblock="${superblock_block}" -o blocksize="${block_size}" "${fs_file}"
            ) || true
        fi
    fi
done

