/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

public class Thumbnail : LayoutItem {
    public const int MIN_SCALE = ThumbnailCache.Size.SMALLEST.get_scale() / 2;
    public const int MAX_SCALE = ThumbnailCache.Size.LARGEST.get_scale();
    public const int DEFAULT_SCALE = ThumbnailCache.Size.MEDIUM.get_scale();
    
    public const Gdk.InterpType LOW_QUALITY_INTERP = Gdk.InterpType.NEAREST;
    public const Gdk.InterpType HIGH_QUALITY_INTERP = Gdk.InterpType.BILINEAR;
    
    private int scale;
    private Dimensions dim;
    private Gdk.InterpType interp = LOW_QUALITY_INTERP;
    private Cancellable cancellable = null;
    
    public Thumbnail(LibraryPhoto photo, int scale = DEFAULT_SCALE) {
        base(photo, photo.get_dimensions().get_scaled(scale, true));
        
        this.scale = scale;
        
        set_title(photo.get_name());

        // store for exposed/unexposed events
        dim = photo.get_dimensions().get_scaled(scale, true);
    }
    
    public LibraryPhoto get_photo() {
        return (LibraryPhoto) get_source();
    }
    
    private override void thumbnail_altered() {
        dim = get_photo().get_dimensions().get_scaled(scale, true);
        
        // only fetch and scale if exposed
        if (is_exposed()) {
            schedule_async_fetch(LOW_QUALITY_INTERP);
        } else {
            cancel_async_fetch();
            clear_image(dim.width, dim.height);
        }

        base.thumbnail_altered();
    }
    
    public bool is_low_quality_thumbnail() {
        return interp != HIGH_QUALITY_INTERP;
    }
    
    public void resize(int new_scale) {
        assert(new_scale >= MIN_SCALE);
        assert(new_scale <= MAX_SCALE);
        
        if (scale == new_scale)
            return;
        
        scale = new_scale;
        
        notify_thumbnail_altered();
    }
    
    public void paint_high_quality() {
        if (!is_exposed() || interp == HIGH_QUALITY_INTERP)
            return;
        
        schedule_async_fetch(HIGH_QUALITY_INTERP);
    }
    
    private void schedule_async_fetch(Gdk.InterpType interp) {
        cancel_async_fetch();
        cancellable = new Cancellable();
        
        // stash interp as current interp, to indicate what's coming in (may be changed while
        // waiting for fetch to complete)
        this.interp = interp;
        ThumbnailCache.fetch_async_scaled(get_photo().get_photo_id(), scale, interp,
            on_pixbuf_fetched, cancellable);
    }
    
    private void cancel_async_fetch() {
        if (cancellable == null)
            return;
        
        cancellable.cancel();
        cancellable = null;
    }
    
    private void on_pixbuf_fetched(Gdk.Pixbuf? pixbuf, int scale, Gdk.InterpType interp, Error? err) {
        if (err != null)
            error("Unable to fetch thumbnail for %s (scale: %d): %s", to_string(), scale, err.message);
        
        assert(pixbuf != null);
        assert(this.scale == scale);
        
        Dimensions pixbuf_dim = Dimensions.for_pixbuf(pixbuf);
        if (!dim.approx_equals(pixbuf_dim))
            debug("Thumbnail: Wanted %s got %s", dim.to_string(), pixbuf_dim.to_string());
        assert(dim.approx_equals(pixbuf_dim));
        
        this.interp = interp;
        set_image(pixbuf);
    }
    
    public override void exposed() {
        if (!is_exposed())
            schedule_async_fetch(LOW_QUALITY_INTERP);

        base.exposed();
    }
    
    public override void unexposed() {
        if (is_exposed()) {
            cancel_async_fetch();
            clear_image(dim.width, dim.height);
        }
        
        base.unexposed();
    }
}
