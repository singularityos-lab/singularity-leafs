# ls

> List the contents of a folder.

- List files, one per line with details:

`ls -l`

- Include hidden files:

`ls -la`

- Sort by modification time, newest first:

`ls -lt`

- Show sizes in a readable form:

`ls -lh {{folder}}`

# cd

> Change the current folder.

- Go to a folder:

`cd {{path/to/folder}}`

- Go to the home folder:

`cd`

- Go up one level:

`cd ..`

- Go back to the previous folder:

`cd -`

# pwd

> Print the path of the current folder.

- Show where you are:

`pwd`

# cp

> Copy files and folders.

- Copy a file:

`cp {{source}} {{destination}}`

- Copy a folder and everything inside it:

`cp -r {{source_folder}} {{destination}}`

- Ask before overwriting:

`cp -i {{source}} {{destination}}`

# mv

> Move or rename files and folders.

- Rename a file:

`mv {{old_name}} {{new_name}}`

- Move a file into a folder:

`mv {{file}} {{folder}}/`

- Ask before overwriting:

`mv -i {{source}} {{destination}}`

# rm

> Remove files and folders. There is no trash: removed files are gone.

- Remove a file:

`rm {{file}}`

- Remove a folder and everything inside it:

`rm -r {{folder}}`

- Ask before each removal:

`rm -i {{files}}`

# mkdir

> Create folders.

- Create a folder:

`mkdir {{folder}}`

- Create nested folders in one go:

`mkdir -p {{path/to/folder}}`

# touch

> Create an empty file or update its modification time.

- Create a file:

`touch {{file}}`

# cat

> Print the contents of files.

- Show a file:

`cat {{file}}`

- Show a file with line numbers:

`cat -n {{file}}`

- Join files into a new one:

`cat {{first}} {{second}} > {{joined}}`

# less

> Read a long file one page at a time. Press q to quit and / to search.

- Open a file:

`less {{file}}`

- Follow a file as it grows, like tail -f:

`less +F {{file}}`

# head

> Show the beginning of a file.

- Show the first 10 lines:

`head {{file}}`

- Show the first lines of a given count:

`head -n {{20}} {{file}}`

# tail

> Show the end of a file.

- Show the last 10 lines:

`tail {{file}}`

- Keep showing new lines as they are written:

`tail -f {{file}}`

- Show the last lines of a given count:

`tail -n {{50}} {{file}}`

# find

> Search for files in a folder tree.

- Find files by name:

`find {{folder}} -name '{{*.txt}}'`

- Find folders only:

`find {{folder}} -type d -name '{{name}}'`

- Find files changed in the last day:

`find {{folder}} -mtime -1`

- Find files bigger than 100 MB:

`find {{folder}} -size +100M`

# grep

> Search for text inside files.

- Search a file for a word:

`grep '{{word}}' {{file}}`

- Search every file in a folder:

`grep -r '{{word}}' {{folder}}`

- Ignore upper and lower case:

`grep -i '{{word}}' {{file}}`

- Show line numbers and two lines around each match:

`grep -n -C 2 '{{word}}' {{file}}`

- Show lines that do not match:

`grep -v '{{word}}' {{file}}`

# sed

> Edit text in a stream, line by line.

- Replace the first match on each line:

`sed 's/{{old}}/{{new}}/' {{file}}`

- Replace every match and save the file in place:

`sed -i 's/{{old}}/{{new}}/g' {{file}}`

- Delete lines that match:

`sed '/{{pattern}}/d' {{file}}`

# awk

> Process text organised in columns.

- Print the second column:

`awk '{print $2}' {{file}}`

- Use a comma as the separator:

`awk -F ',' '{print $1}' {{file.csv}}`

- Add up the numbers in the first column:

`awk '{sum += $1} END {print sum}' {{file}}`

# sort

> Sort lines of text.

- Sort alphabetically:

`sort {{file}}`

- Sort numbers, largest first:

`sort -nr {{file}}`

- Sort and remove duplicates:

`sort -u {{file}}`

# uniq

> Remove or count repeated lines. Sort the input first.

- Count how often each line appears:

`sort {{file}} | uniq -c`

- Show only repeated lines:

`sort {{file}} | uniq -d`

# wc

> Count lines, words and bytes.

- Count lines:

`wc -l {{file}}`

- Count words:

`wc -w {{file}}`

# cut

> Pick columns or characters from each line.

- Take the first field of a colon separated file:

`cut -d ':' -f 1 {{/etc/passwd}}`

- Take the first ten characters:

`cut -c 1-10 {{file}}`

# tr

> Translate or delete characters.

- Turn lowercase into uppercase:

`tr 'a-z' 'A-Z' < {{file}}`

- Delete every digit:

`tr -d '0-9' < {{file}}`

# xargs

> Build commands from standard input.

- Remove every file that find returns:

`find {{folder}} -name '{{*.tmp}}' -print0 | xargs -0 rm`

- Run a command once per line:

`xargs -n 1 {{command}} < {{list}}`

# tee

> Write output to a file and to the screen at the same time.

- Save and show output:

`{{command}} | tee {{file}}`

- Append instead of overwriting:

`{{command}} | tee -a {{file}}`

# diff

> Compare files line by line.

- Show the differences between two files:

`diff {{old}} {{new}}`

- Show them in unified format, as patches do:

`diff -u {{old}} {{new}}`

- Compare two folders:

`diff -r {{folder_a}} {{folder_b}}`

# ln

> Create links to files.

- Create a symbolic link:

`ln -s {{target}} {{link_name}}`

- Point an existing link somewhere else:

`ln -sf {{new_target}} {{link_name}}`

- Create a hard link:

`ln {{target}} {{link_name}}`

# chmod

> Change who can read, write or run a file.

- Make a script runnable:

`chmod +x {{script}}`

- Let only the owner read and write:

`chmod 600 {{file}}`

- Apply to a folder and everything inside:

`chmod -R {{u+rwX}} {{folder}}`

# chown

> Change the owner of files.

- Give a file to a user and group:

`sudo chown {{user}}:{{group}} {{file}}`

- Apply to a folder and everything inside:

`sudo chown -R {{user}} {{folder}}`

# du

> Show how much space files and folders use.

- Size of a folder:

`du -sh {{folder}}`

- Size of each item here, largest last:

`du -sh * | sort -h`

# df

> Show free space on each disk.

- Show free space in a readable form:

`df -h`

- Show the disk that holds a folder:

`df -h {{folder}}`

# free

> Show memory use.

- Show memory in a readable form:

`free -h`

# top

> Show running programs and what they use, live. Press q to quit.

- Start the monitor:

`top`

- Sort by memory:

`top -o %MEM`

# ps

> List running processes.

- List every process with details:

`ps aux`

- Find a process by name:

`ps aux | grep {{name}}`

- Show processes as a tree:

`ps -ef --forest`

# kill

> Send a signal to a process, usually to stop it.

- Ask a process to stop:

`kill {{process_id}}`

- Force a process to stop at once:

`kill -9 {{process_id}}`

- List the signal names:

`kill -l`

# pgrep

> Find process ids by name.

- Find a process:

`pgrep -a {{name}}`

# jobs

> Manage programs started from this terminal.

- List background jobs:

`jobs`

- Run a command in the background:

`{{command}} &`

- Bring the last job back to the front:

`fg`

- Continue a paused job in the background:

`bg`

# nohup

> Keep a command running after the terminal closes.

- Run a command that survives the terminal:

`nohup {{command}} > {{log.txt}} 2>&1 &`

# history

> Show the commands you typed before.

- Show the history:

`history`

- Search the history for a word:

`history | grep {{word}}`

- Run the previous command again:

`!!`

# alias

> Give a short name to a longer command.

- Create an alias for this session:

`alias {{ll}}='{{ls -la}}'`

- List every alias:

`alias`

- Remove an alias:

`unalias {{ll}}`

# echo

> Print text.

- Print a message:

`echo '{{Hello}}'`

- Print the value of a variable:

`echo "$HOME"`

- Write a line to a file:

`echo '{{text}}' >> {{file}}`

# env

> Show or change environment variables for a command.

- Show every environment variable:

`env`

- Run a command with a variable set:

`env {{NAME}}={{value}} {{command}}`

# export

> Set an environment variable for this session and the programs it starts.

- Set a variable:

`export {{NAME}}={{value}}`

- Add a folder to the command search path:

`export PATH="$PATH:{{path/to/folder}}"`

# which

> Show where a command lives.

- Find the program behind a command:

`which {{command}}`

- Show every match, including aliases and functions:

`type -a {{command}}`

# man

> Read the manual of a command. Press q to quit.

- Open a manual page:

`man {{command}}`

- Search manual pages by keyword:

`man -k {{keyword}}`

# tar

> Create and extract archives, also called tarballs.

- Extract an archive here:

`tar -xf {{archive.tar.gz}}`

- Compress a folder into an archive:

`tar -czf {{archive.tar.gz}} {{folder}}`

- List what an archive contains:

`tar -tf {{archive.tar}}`

- Extract into a given folder:

`tar -xf {{archive.tar.xz}} -C {{folder}}`

# zip

> Create zip archives, compressing files and folders.

- Compress a folder into a zip archive:

`zip -r {{archive.zip}} {{folder}}`

# unzip

> Extract zip archives.

- Extract here:

`unzip {{archive.zip}}`

- Extract into a folder:

`unzip {{archive.zip}} -d {{folder}}`

- List what the archive contains:

`unzip -l {{archive.zip}}`

# gzip

> Compress or uncompress single files.

- Compress a file:

`gzip {{file}}`

- Uncompress a file:

`gunzip {{file.gz}}`

# xz

> Compress files with a high ratio.

- Compress a file and keep the original:

`xz -k {{file}}`

- Uncompress a file:

`unxz {{file.xz}}`

# curl

> Transfer data from or to a server.

- Download a file and keep its name:

`curl -LO {{https://example.com/file}}`

- Show only the response headers:

`curl -I {{https://example.com}}`

- Send a JSON file:

`curl -X POST -H 'Content-Type: application/json' -d @{{data.json}} {{https://example.com/api}}`

# wget

> Download files from the web.

- Download a file:

`wget {{https://example.com/file}}`

- Resume a broken download:

`wget -c {{https://example.com/file}}`

# ssh

> Open a secure shell on another computer.

- Connect to a computer:

`ssh {{user}}@{{host}}`

- Connect on another port:

`ssh -p {{2222}} {{user}}@{{host}}`

- Run one command remotely:

`ssh {{user}}@{{host}} '{{command}}'`

- Forward a local port to the remote computer:

`ssh -L {{8080}}:localhost:{{80}} {{user}}@{{host}}`

# ssh-keygen

> Create keys for signing in without a password.

- Create a new key:

`ssh-keygen -t ed25519`

- Copy your key to another computer:

`ssh-copy-id {{user}}@{{host}}`

# scp

> Copy files over ssh.

- Send a file to another computer:

`scp {{file}} {{user}}@{{host}}:{{path}}`

- Fetch a file from another computer:

`scp {{user}}@{{host}}:{{path/to/file}} .`

- Copy a folder:

`scp -r {{folder}} {{user}}@{{host}}:{{path}}`

# rsync

> Copy and synchronise files, sending only what changed.

- Copy a folder and keep permissions and times:

`rsync -a {{source}}/ {{destination}}/`

- Show progress while copying to another computer:

`rsync -avP {{source}}/ {{user}}@{{host}}:{{destination}}/`

- Make the destination an exact copy, removing extra files:

`rsync -a --delete {{source}}/ {{destination}}/`

# ping

> Check whether another computer answers.

- Ping a host:

`ping {{example.com}}`

- Send a set number of pings:

`ping -c {{4}} {{example.com}}`

# ip

> Show and change network settings.

- Show addresses:

`ip address`

- Show routes:

`ip route`

- Show network devices:

`ip link`

# ss

> Show network connections and listening ports.

- Show listening ports and the programs behind them:

`ss -tulpn`

# dig

> Look up names in DNS.

- Look up an address:

`dig {{example.com}}`

- Show only the answer:

`dig +short {{example.com}}`

# git

> Track changes in a project.

- Show what changed:

`git status`

- Stage and commit everything:

`git commit -am '{{message}}'`

- Show recent history on one line each:

`git log --oneline -n {{10}}`

- Create and switch to a new branch:

`git switch -c {{branch}}`

- Download and merge the latest changes:

`git pull`

- Put local changes aside for later:

`git stash`

# sudo

> Run a command as the administrator.

- Run a command as administrator:

`sudo {{command}}`

- Run the previous command as administrator:

`sudo !!`

- Edit a system file safely:

`sudoedit {{/etc/hosts}}`

# systemctl

> Control services on systems that use systemd.

- Show the state of a service:

`systemctl status {{service}}`

- Start or stop a service:

`sudo systemctl {{start}} {{service}}`

- List failed services:

`systemctl --failed`

# journalctl

> Read the system log on systems that use systemd.

- Follow the log as it is written:

`journalctl -f`

- Show messages from this boot:

`journalctl -b`

- Show messages of one service:

`journalctl -u {{service}}`

# dmesg

> Read kernel messages.

- Show kernel messages with readable times:

`sudo dmesg -T`

# uname

> Show information about the system.

- Show the kernel version:

`uname -r`

- Show everything:

`uname -a`

# lsblk

> List disks and partitions.

- Show disks, partitions and where they are mounted:

`lsblk -f`

# mount

> Attach a file system to a folder.

- Mount a partition:

`sudo mount {{/dev/sdb1}} {{/mnt}}`

- Unmount it:

`sudo umount {{/mnt}}`

- Show what is mounted:

`findmnt`

# date

> Show or format the date and time.

- Show the date and time:

`date`

- Show it in ISO format:

`date -I`

- Show Unix time:

`date +%s`

# watch

> Run a command again and again and show its output.

- Repeat a command every two seconds:

`watch {{command}}`

- Repeat every second and highlight changes:

`watch -n 1 -d {{command}}`

# crontab

> Run commands on a schedule.

- Edit your schedule:

`crontab -e`

- List your schedule:

`crontab -l`

# file

> Find out what kind of file something is.

- Show the type of a file:

`file {{file}}`

# stat

> Show details about a file.

- Show size, permissions and times:

`stat {{file}}`

# whoami

> Show which user you are.

- Print your user name:

`whoami`

- Show your user and group ids:

`id`

# passwd

> Change a password.

- Change your password:

`passwd`

# flatpak

> Install and run Flatpak apps.

- Search for an app:

`flatpak search {{name}}`

- Install an app from Flathub:

`flatpak install flathub {{app.id}}`

- Update every app:

`flatpak update`

- List installed apps:

`flatpak list --app`

# python3

> Run Python.

- Start an interactive session:

`python3`

- Run a script:

`python3 {{script.py}}`

- Share the current folder on port 8000:

`python3 -m http.server {{8000}}`

- Create a virtual environment:

`python3 -m venv {{.venv}}`

# nano

> A simple text editor in the terminal. Ctrl+O saves, Ctrl+X quits.

- Edit a file:

`nano {{file}}`

# vim

> A powerful text editor in the terminal. Type :wq to save and quit, :q! to quit without saving.

- Edit a file:

`vim {{file}}`

- Open a file at a given line:

`vim +{{42}} {{file}}`

# seq

> Print a sequence of numbers.

- Count from one to ten:

`seq 1 10`

# for

> Repeat commands for each item.

- Run a command for every file here:

`for f in *; do {{echo "$f"}}; done`

# test

> Check conditions in scripts.

- Run a command only if a file exists:

`[ -f {{file}} ] && {{command}}`

# base64

> Encode and decode Base64.

- Encode a file:

`base64 {{file}}`

- Decode text:

`base64 -d <<< '{{text}}'`

# sha256sum

> Check files with a SHA-256 checksum.

- Print the checksum of a file:

`sha256sum {{file}}`

- Check files against a list of checksums:

`sha256sum -c {{SHA256SUMS}}`

# lsof

> Show which programs have files open.

- Show who uses a port:

`lsof -i :{{8080}}`

# nproc

> Show how many processors are available.

- Print the number of processors:

`nproc`
