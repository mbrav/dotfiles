function extract -d "Extract archive files by detected type"
    if test (count $argv) -eq 0
        echo "Usage: extract <file> [more...]"
        return 1
    end

    for file in $argv
        if not test -f "$file"
            echo "extract: '$file': file not found" >&2
            continue
        end

        switch "$file"
            case '*.tar.gz' '*.tgz'
                tar xzf "$file"
            case '*.tar.bz2'
                tar xjf "$file"
            case '*.tar.xz'
                tar xJf "$file"
            case '*.tar.zst'
                if not command -q zstd
                    echo "extract: zstd not installed" >&2
                    continue
                end
                tar --use-compress-program=zstd -xf "$file"
            case '*.tar'
                tar xf "$file"
            case '*.gz'
                if not command -q gunzip
                    echo "extract: gunzip not installed" >&2
                    continue
                end
                gunzip "$file"
            case '*.bz2'
                if not command -q bunzip2
                    echo "extract: bunzip2 not installed" >&2
                    continue
                end
                bunzip2 "$file"
            case '*.xz'
                if not command -q xz
                    echo "extract: xz not installed" >&2
                    continue
                end
                xz -d "$file"
            case '*.zst'
                if not command -q zstd
                    echo "extract: zstd not installed" >&2
                    continue
                end
                zstd -d "$file"
            case '*.zip'
                if not command -q unzip
                    echo "extract: unzip not installed" >&2
                    continue
                end
                unzip "$file"
            case '*.7z'
                if not command -q 7z
                    echo "extract: 7z not installed" >&2
                    continue
                end
                7z x "$file"
            case '*.rar'
                if not command -q unrar
                    echo "extract: unrar not installed" >&2
                    continue
                end
                unrar x "$file"
            case '*'
                echo "extract: '$file': unknown archive format" >&2
                continue
        end
    end
end
