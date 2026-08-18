# Guards for the Arch package managers, and the sudo alias they need.
#
# pacman and yay are answered with a reminder instead of running: on Omarchy
# packages go in and out through omarchy, and reaching past it leaves the machine
# in a state omarchy did not put it in.
#
# The reminder names the command that actually replaces what was typed, since
# "use omarchy" alone does not say which of these it meant:
#
#   pacman -S <pkg>     ->  omarchy pkg add <pkg>
#   pacman -R <pkg>     ->  omarchy pkg drop <pkg>
#   pacman -Syu         ->  omarchy update
#   yay -S <pkg>        ->  omarchy pkg aur add <pkg>
#   yay                 ->  omarchy pkg aur install   (picker)
#
# The trailing space in the sudo alias is what makes "sudo pacman" hit the guard
# too -- bash only looks at the word after an alias for another alias when the
# alias ends in a space.
#
# Optional: install-bash-config.sh asks before installing this file, since these
# same three come with Omarchy and you may prefer to leave them to it.

alias sudo='sudo '
alias pacman='echo "Use omarchy pkg add <pkg> / omarchy pkg drop <pkg> / omarchy update"; false'
alias yay='echo "Use omarchy pkg aur add <pkg> / omarchy pkg aur install / omarchy update"; false'
