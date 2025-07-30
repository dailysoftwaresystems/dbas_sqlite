#!/bin/bash
set -e

if command -v xcodebuild &> /dev/null; then
  sudo xcodebuild -license accept
fi

if ! xcode-select -p &> /dev/null; then
  echo "Installing Command Line Tools..."
  xcode-select --install
else
  echo "Command Line Tools already installed. Checking updates..."
  softwareupdate --list | grep -q "Command Line Tools" && sudo softwareupdate -i "$(softwareupdate --list | grep -oE 'Command Line Tools.*\n' | head -n1 | sed 's/^[ *]*//')"
fi

brew install rbenv ruby ruby-build
echo 'eval "$(rbenv init -)"' >> ~/.zshrc
echo 'export PATH="/opt/homebrew/opt/ruby/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc

sudo gem install cocoapods
sudo gem update

echo "All dependencies installed."