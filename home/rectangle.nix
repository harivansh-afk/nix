{lib, ...}: {
  home.activation.importRectanglePreferences = lib.hm.dag.entryAfter ["writeBoundary"] ''
    /usr/bin/defaults import com.knollsoft.Rectangle ${../config/rectangle/Rectangle.plist}
  '';
}
