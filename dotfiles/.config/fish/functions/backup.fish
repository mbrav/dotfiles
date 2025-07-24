# backup.fish - Simple function to create a backup of a file
# Usage: backup <filename>
# Copies <filename> to <filename>.bak
function backup --argument filename -d "Backup file"
    cp $filename $filename.bak
end

function backup --argument filename -d "Backup file"
    cp $filename $filename.bak
end
