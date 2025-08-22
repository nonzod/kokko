#!/usr/bin/env bash

# Set PS1 so we know we're in the container
cat > .bashrc <<EOF
alias ls='ls --color'
export PS1="${debian_chroot:+($debian_chroot)}\u@dz-web:\w\$ "
export TERM=screen.xterm-256color
unset DEVELOPMENT
EOF

# Shut steamcmd up
if ! [ -d ${HOME}/.steam ]
then
	mkdir -p ${HOME}/.steam
fi

cd /web
npm i
export DEBUG='express:*'
npx nodemon web.js &

cd docroot
npm i
exec npm run dev
