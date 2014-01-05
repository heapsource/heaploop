module heaploop.streams;
import heaploop.looping;
import events;
import duv.c;
import duv.types;
import core.thread;
debug {
    import std.stdio;
}

abstract class Stream : Looper {
        alias FiberedEventList!(void, Stream, ubyte[]) readEventList;
    private:
        uv_stream_t * _handle;
        Loop _loop;
        readEventList _readEvent;
        readEventList.Trigger _readTrigger;
        bool _isReading;

    public:

        this(Loop loop, uv_handle_type type) {
            import std.c.stdlib : malloc;
            _loop = loop;
            _handle = cast(uv_stream_t*)duv__handle_alloc(type);
            this.init();
        }

        ~this() {
            debug std.stdio.writeln("Destroying stream");
        }

        @property Loop loop() {
            return _loop;
        }

        @property uv_stream_t* handle() {
            return _handle;
        }

        void write(ubyte[] data) {
            auto wc = new OperationContext!Stream(this);
            duv_write(this.handle, wc, data, function (uv_stream_t * thisHandle, contextObj, status writeStatus) {
                    auto wc = cast(OperationContext!Stream)contextObj;
                    wc.resume(writeStatus);
            });
            wc.yield;
            wc.completed;
            debug std.stdio.writeln("Write completed");
        }

        readEventList read() {
            _readEvent = new readEventList;
            _readTrigger = _readEvent.own((trigger, activated) {
                auto rx = new OperationContext!Stream(this);
                if(activated) {
                    rx.target._isReading = true;
                    duv_read_start(_handle, rx, (uv_stream_t * client_conn, Object readContext, ptrdiff_t nread, ubyte[] data) {
                        auto rx = cast(OperationContext!Stream)readContext;
                        Stream thisStream = rx.target;
                        int status = cast(int)nread;

                        if(status.isError) {
                            debug std.stdio.writeln("read callback error");
                            rx.resume(status);
                        } else {
                            thisStream._readTrigger(thisStream, data);
                        }
                    });
                    debug std.stdio.writeln("read (activated block) will yield");
                    rx.yield;
                    debug std.stdio.writeln("read (activated block) continue after yield");
                    rx.target._isReading = false;
                    duv_read_stop(this.handle);
                    rx.completed;
                } else {
                    debug std.stdio.writeln("read deactivation");
                    rx.resume;
                }
            });
            return _readEvent;
        }

        void stopReading() {
            if(_readTrigger) {
                debug std.stdio.writeln("stopReading: reseting trigger");
                auto t = _readTrigger;
                _readEvent = null;
                _readTrigger = null;
                t.reset();
            } else {
                debug std.stdio.writeln("(stopReading had no effect");
            }
        }

        void close() {
            closeCleanup();
            auto cx = new OperationContext!Stream(this);
            duv_handle_close(cast(uv_handle_t*)this.handle, cx, function (uv_handle_t * handle, context) {
                    auto cx = cast(OperationContext!Stream)context;
                    cx.resume;
            });
            cx.yield;
            cx.completed;
        }

        void closeCleanup() {
            stopReading();
        }

    protected:

        abstract void init();


}
