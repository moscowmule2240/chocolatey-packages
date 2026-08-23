$ErrorActionPreference = 'Stop'

# Automatic shims go when Chocolatey removes the package folder. The r2 alias was
# registered explicitly, so it has to be removed explicitly or the command lingers.
Uninstall-BinFile -Name 'r2'
