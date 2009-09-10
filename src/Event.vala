/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

// A ClassNotifier is designed for many-to-one signalling in large-scale situations.  There are
// times when a single object wants to be signalled on changes on many (or all) of a type of
// object in the system.
public class ClassNotifier {
}

public class EventNotifier : ClassNotifier {
    public signal void added(Event event);
    
    public signal void altered(Event event);
    
    public signal void removed(Event event);
}

public class Event : Object, Queryable, EventSource {
    public const long EVENT_LULL_SEC = 3 * 60 * 60;
    public const long EVENT_MAX_DURATION_SEC = 12 * 60 * 60;
    
    public static EventNotifier notifier = null;
    
    private static Gee.HashMap<int64?, Event> event_map = null;
    private static EventTable event_table = null;

    private EventID event_id;
    
    public virtual signal void altered() {
    }
    
    public virtual signal void removed() {
    }
    
    private Event(EventID event_id) {
        this.event_id = event_id;
    }
    
    public static void init() {
        event_map = new Gee.HashMap<int64?, Event>(int64_hash, int64_equal, direct_equal);
        event_table = new EventTable();
        notifier = new EventNotifier();
        
        // Event watches LibraryPhoto for removals
        LibraryPhoto.notifier.removed += on_photo_removed;
    }
    
    public static void terminate() {
    }
    
    public static Gee.ArrayList<Event> fetch_all() {
        Gee.ArrayList<EventID?> events = event_table.get_events();
        
        Gee.ArrayList<Event> all = new Gee.ArrayList<Event>();
        foreach (EventID event_id in events)
            all.add(fetch(event_id));
        
        return all;
    }
    
    public static Event fetch(EventID event_id) {
        Event event = event_map.get(event_id.id);
        if (event == null) {
            event = new Event(event_id);
            event_map.set(event_id.id, event);
        }
        
        return event;
    }
    
    private static void notify_added(Event event) {
        notifier.added(event);
    }
    
    private void notify_altered() {
        altered();
        notifier.altered(this);
    }
    
    private void notify_removed() {
        removed();
        notifier.removed(this);
    }
    
    // Event needs to know whenever a photo is removed from the system to update the event
    private static void on_photo_removed(LibraryPhoto photo) {
        // update event's primary photo if this is the one; remove event if no more photos in it
        Event event = photo.get_event();
        if (event != null && event.get_primary_photo() == photo) {
            Gee.Iterable<PhotoSource> photos = event.get_photos();
            
            LibraryPhoto found = null;
            // TODO: For now, simply selecting the first photo possible
            foreach (PhotoSource event_photo in photos) {
                if (photo != (LibraryPhoto) event_photo) {
                    found = (LibraryPhoto) event_photo;
                    
                    break;
                }
            }
            
            if (found != null) {
                event.set_primary_photo(found);
            } else {
                // this indicates this is the last photo of the event, so no more event
                assert(event.get_photo_count() <= 1);
                event.remove();
            }
        }
    }
    
    public static void generate_events(SortedList<LibraryPhoto> imported_photos) {
        debug("Processing imported photos to create events ...");

        // walk through photos, splitting into events based on criteria
        time_t last_exposure = 0;
        time_t current_event_start = 0;
        Event current_event = null;
        foreach (LibraryPhoto photo in imported_photos) {
            time_t exposure_time = photo.get_exposure_time();

            if (exposure_time == 0) {
                // no time recorded; skip
                debug("Skipping event assignment to %s: No exposure time", photo.to_string());
                
                continue;
            }
            
            if (photo.get_event() != null) {
                // already part of an event; skip
                debug("Skipping event assignment to %s: Already part of event %s", photo.to_string(),
                    photo.get_event().to_string());
                    
                continue;
            }
            
            // see if enough time has elapsed to create a new event, or to store this photo in
            // the current one
            bool create_event = false;
            if (last_exposure == 0) {
                // first photo, start a new event
                create_event = true;
            } else {
                assert(last_exposure <= exposure_time);
                assert(current_event_start <= exposure_time);

                if (exposure_time - last_exposure >= EVENT_LULL_SEC) {
                    // enough time has passed between photos to signify a new event
                    create_event = true;
                } else if (exposure_time - current_event_start >= EVENT_MAX_DURATION_SEC) {
                    // the current event has gone on for too long, stop here and start a new one
                    create_event = true;
                }
            }
            
            if (create_event) {
                if (current_event != null) {
                    assert(last_exposure != 0);
                    current_event.set_end_time(last_exposure);
                    
                    notify_added(current_event);
                    
                    debug("Reported event creation %s", current_event.to_string());
                }

                current_event_start = exposure_time;
                current_event = Event.fetch(
                    event_table.create(photo.get_photo_id(), current_event_start));

                debug("Created event %s", current_event.to_string());
            }
            
            assert(current_event != null);
            
            debug("Adding %s to event %s (exposure=%ld last_exposure=%ld)", photo.to_string(), 
                current_event.to_string(), exposure_time, last_exposure);
            
            photo.set_event(current_event);

            last_exposure = exposure_time;
        }
        
        // mark the last event's end time
        if (current_event != null) {
            assert(last_exposure != 0);
            current_event.set_end_time(last_exposure);
            
            notify_added(current_event);
            
            debug("Reported event creation %s", current_event.to_string());
        }
    }

    public EventID get_event_id() {
        return event_id;
    }
    
    public bool equals(Event event) {
        // due to the event_map, identity should be preserved by pointers, but ID is the true test
        if (this == event) {
            assert(event_id.id == event.event_id.id);
            
            return true;
        }
        
        assert(event_id.id != event.event_id.id);
        
        return false;
    }
    
    public string to_string() {
        return "[%lld] %s".printf(event_id.id, get_name());
    }
    
    public string get_name() {
        return event_table.get_name(event_id);
    }
    
    public string? get_raw_name() {
        return event_table.get_raw_name(event_id);
    }
    
    public bool rename(string name) {
        bool renamed = event_table.rename(event_id, name);
        if (renamed)
            notify_altered();
        
        return renamed;
    }
    
    public time_t get_start_time() {
        return event_table.get_start_time(event_id);
    }
    
    public time_t get_end_time() {
        return event_table.get_end_time(event_id);
    }
    
    public bool set_end_time(time_t end_time) {
        bool committed = event_table.set_end_time(event_id, end_time);
        if (committed)
            notify_altered();
        
        return committed;
    }
    
    public uint64 get_total_filesize() {
        return (new PhotoTable()).get_event_photo_filesize(event_id);
    }
    
    public int get_photo_count() {
        return (new PhotoTable()).get_event_photo_count(event_id);
    }
    
    public Gee.Iterable<PhotoSource> get_photos() {
        Gee.ArrayList<PhotoID?> photos = (new PhotoTable()).get_event_photos(event_id);
        
        Gee.ArrayList<PhotoSource> result = new Gee.ArrayList<PhotoSource>();
        foreach (PhotoID photo_id in photos)
            result.add(LibraryPhoto.fetch(photo_id));
        
        return result;
    }
    
    public LibraryPhoto get_primary_photo() {
        return LibraryPhoto.fetch(event_table.get_primary_photo(event_id));
    }
    
    public bool set_primary_photo(LibraryPhoto photo) {
        bool committed = event_table.set_primary_photo(event_id, photo.get_photo_id());
        if (committed)
            notify_altered();
        
        return committed;
    }
    
    public Gdk.Pixbuf? get_preview_pixbuf(Scaling scaling) {
        return get_primary_photo().get_preview_pixbuf(scaling);
    }

    public void remove() {
        // signal that the event is being removed
        notify_removed();

        // remove from the database
        event_table.remove(event_id);
        
        // mark all photos for this event as now event-less
        (new PhotoTable()).drop_event(event_id);
   }
}
