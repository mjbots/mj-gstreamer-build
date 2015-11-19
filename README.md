custom gstreamer build

The stock gstreamer in ubuntu has some annoying bugs. Upgrading .deb files
from ppa breakes other packages. The script here compiles gstreamer into /opt
directory, then packages it to .tar.bz2 file.

This is a separate repository from mjmech because it contains large files
(~150MB).
