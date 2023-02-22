#!/usr/local/bin/fish

set mbrav_scripts_v "0.1.4"
set script_id "mbrav/configs v$mbrav_scripts_v"

function load_starship
    if type -q starship
        set --temp major (count $BASH_VERSINFO - 1)
        set minor (echo $BASH_VERSINFO[$major] | cut -d . -f2)
        if test (math "$major > 4") or (and (math "$major == 4") (math "$minor >= 1"))
            . (starship init fish --print-full-init)
        else
            eval (starship init fish --print-full-init)
        end
    end
end

# If interactive, don't do anything
if not test -t 0
    return
end

load_starship

function check_sudo
    if test "$USER" != "root"
        printf "%b%s\n"  (set_color red) (set_color bold)[X] (set_color normal)Please run script as root or sudo
        exit 13
    else
        printf "%bNote: to run sudo and preserve passed env variables run with 'sudo -E'\n" (set_color yellow) (set_color bold)
    end
end

function yes_no_prompt
    # %arg1 - Space separated string for prompt
    # Sets $Y_N to:
    # 0 - yes
    # 1 - no
    set yes_no_finish 1
    while test $yes_no_finish != 0
        printf "%b%s (%b%s%b) y/n:%b " \
            (set_color green) (set_color bold)$argv[1] (set_color yellow) (set_color bold) (set_color normal)
        read Y_N
        switch -q $Y_N
            case 'y' 'Y' 'yes'
                set yes_no_finish 0
                set Y_N 0
            case 'n' 'N' 'no'
                set yes_no_finish 0
                set Y_N 1
            (*)
                printf "%b%s %b%s%b is not a yes/no option!\n"  (set_color red) (set_color bold)[X] (set_color normal) $Y_N
        end
    end
end

function check_url
    # 0 - exists
    # 1 - does not
    if curl --output /dev/null --silent --head --fail $argv[1];
        echo 0
    else
        echo 1
    end
end

function docker-compose-install
    # %arg1 - Docker compsoe version, otherwise default
    if string length $argv[1] > 0
        set docker_v $argv[1]
    else
        set docker_v 2.12.2
    end
    set docker_url "https://github.com/docker/compose/releases/download/v$docker_v/docker-compose-$(uname -s)-$(uname -m)"
    if test $(check_url $docker_url) = 0
        printf "%bValid url: %b%s\n" (set_color green) (set_color normal)$docker_url
        sudo curl -L $docker_url -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
        printf "%b%s\n" (set_color green)gocker compose installed
        docker-compose --version
    end
end

function replace-vars
    # $1 - string to find
    # $2 - string to change to
    # $3 - File path
    if test (count $argv) ne 3
        echo "replace_vars() accepts 3 arguments, not $(count $argv)"
        exit 22
    end

    echo "Will replace '$argv[1]' with '$argv[2]' in file $argv[3]"
    set grep_command (grep "$argv[1]" "$argv[3]")
    echo "Before:"
    echo -e $BLUE"$grep_command"

    sed -i 's,"$argv[1]",$argv[2],g' "$argv[3]"

    set grep_command (grep "$argv[2]" "$argv[3]")
    echo "After:"
    echo -e $BLUE"$grep_command"
end

function dock-save
    if test (count $argv) lt 1 or (count $argv) gt 2
        echo -e $RED"Must provide 2 arguments, docker image name and tar output file name (no exension)"$CLEAR
        exit 1
    end
    mkdir -p ~/docker-images
    echo -e $GREEN"Exporting image $YELLOW$argv[1] $GREEN to ~/docker-images/$YELLOW$argv[2].tar.gz"$CLEAR
    docker save $argv[1] | gzip -c > ~/docker-images/$argv[2].tar.gz
end

function _dock-save_completions
    if (count $argv) != 2
        return
    else
        set COMPREPLY (docker images --format "{{.Repository}}:{{.Tag}}")
    end
end

complete -F _dock-save_completions dock-save


function nmap-gen
    # $1 - IP range
    # Nmap scanner and report generation
    # $2 - report name

    if not (type nmap >/dev/null)
        echo "nmap not installed!"
        exit 1
    elseif not (type xsltproc >/dev/null)
        echo "xsltproc not installed!"
        exit 1
    end

    if not test -z $argv[1] 
        set ip_range $argv[1]
    else
        set ip_range "192.168.1.0/24"
    end
    
    if not test -z $argv[2]
        set scan_name $argv[2]
    else
        set scan_name "nmap_scan"
    end

    echo "IP range: $ip_range"
    echo "Scan name: $scan_name"

    nmap -sTV -A -oX $scan_name.xml --webxml $ip_range; and xsltproc $scan_name.xml -o $scan_name.html; and rm $scan_name.xml
end

function do-interval
    # Interval command
    # do-interval 1
    # $1 - interval in seconds 
    # $2-n - command and any number of arguments to execute
    if test (count $argv) lt 2
        echo "do-interval accepts no less than 2 arguments, passed $(count $argv)"
        exit 22
    elseif not test $argv[1] =~ ?(-)+([[:digit:]])
        echo "$argv[1] is not a  number"
        exit 22
    end
    watch -n $argv[1] -d=cumulative ${argv[2..-1]}
end

function 7z-max
  # 7z max compression using lzma2
  echo -e $GREEN$BOLD"7z max compression using lzma2"$CLEAR
  echo -e $YELLOW$BOLD"arg1$CLEAR - archive name without extension"
  echo -e $YELLOW$BOLD"arg2$CLEAR - folder name (optional)"
  if count $argv 0 =
    echo -e $RED$BOLD"Please provide at least one argument"$CLEAR
    exit 1
  end
  set folder_name "$argv[1]"
  if count $argv 1 > 0
    set folder_name $argv[2]
  end
  echo -e (if count $argv 1 = 0 "No folder name provided, using" else "" end) $YELLOW$folder_name$CLEAR
  7z a -m0=lzma2 -mx $argv[1].7z $folder_name
end

function ascii-clean
  # Clean non ascii chars from a file
  set temp_file (rand-hex-ssl 6).tmp
  tr -cd '\11\12\15\40-\176' < $argv[1] > $temp_file
  mv $temp_file $argv[1]
end

function git-cred
  if string match --regexp (status -f $USER/dev/work/**/*) ""
    # markdown syntax not supported by fish. Can consider using other highlighting
    git-cred-mbrav
  else
    git-cred-mbrav
  end
  echo "User:  $(git config user.name)"
  echo "Email: $(git config user.email)"
  echo "Key:   $(git config user.signingkey)"
end

# Attach to tmux session on shell login
function start_tmux
    if type tmux >/dev/null
        # Check if term is inside an IDE or other environments
        # If so, do not enter a tmux session
        if test -n $TERM_PROGRAM; and contains $TERM_PROGRAM vscode my_ide_name
            set no_tmux true
        end

        # Check if inside a SSH session
        if test -n $SSH_CONNECTION; and test -n $SSH_CLIENT; and test -n "$SSH_TTY"
            set no_tmux true
        end

        # Attach to an existing session or create a new one if not present
        if test -z "$TMUX"; and test -z "$TERMINAL_CONTEXT"; and test -z "$no_tmux"
            tmux -2 attach; or tmux -2 new-session
        end
    end
end

start_tmux
