from libc.stdint cimport int64_t, int32_t, uint32_t, uint8_t
from posix.unistd cimport off_t
import time

cdef extern from "Python.h":
    void PyEval_InitThreads()

cdef extern from "zcm/zcm.h":
    cpdef enum zcm_return_codes:
        ZCM_EOK,
        ZCM_EINVALID,
        ZCM_EAGAIN,
        ZCM_ECONNECT,
        ZCM_EINTR,
        ZCM_EUNKNOWN,
        ZCM_NUM_RETURN_CODES
    ctypedef struct zcm_t:
        pass
    ctypedef struct zcm_sub_t:
        pass
    ctypedef struct zcm_recv_buf_t:
        uint8_t* data
        uint32_t data_size
        pass
    ctypedef void (*zcm_msg_handler_t)(const zcm_recv_buf_t* rbuf, const char* channel, void* usr)

    zcm_t* zcm_create (const char* url)
    void   zcm_destroy(zcm_t* zcm)

    int         zcm_errno   (zcm_t* zcm)
    const char* zcm_strerror(zcm_t* zcm)
    const char* zcm_strerrno(int err)

    zcm_sub_t* zcm_try_subscribe  (zcm_t* zcm, const char* channel, zcm_msg_handler_t cb, void* usr)
    int        zcm_try_unsubscribe(zcm_t* zcm, zcm_sub_t* sub)

    int  zcm_publish(zcm_t* zcm, const char* channel, const uint8_t* data, uint32_t dlen)

    int  zcm_try_flush         (zcm_t* zcm)

    void zcm_run               (zcm_t* zcm)
    void zcm_start             (zcm_t* zcm)
    int  zcm_try_stop          (zcm_t* zcm)
    void zcm_pause             (zcm_t* zcm)
    void zcm_resume            (zcm_t* zcm)
    int  zcm_handle            (zcm_t* zcm)
    int  zcm_try_set_queue_size(zcm_t* zcm, uint32_t numMsgs)

    int  zcm_handle_nonblock(zcm_t* zcm)

    ctypedef struct zcm_eventlog_t:
        pass
    ctypedef struct zcm_eventlog_event_t:
        int64_t  eventnum
        int64_t  timestamp
        int32_t  channellen
        int32_t  datalen
        char*    channel
        uint8_t* data

    zcm_eventlog_t* zcm_eventlog_create(const char* path, const char* mode)
    void            zcm_eventlog_destroy(zcm_eventlog_t* eventlog)

    int zcm_eventlog_seek_to_timestamp(zcm_eventlog_t* eventlog, int64_t ts)

    zcm_eventlog_event_t* zcm_eventlog_read_next_event(zcm_eventlog_t* eventlog)
    zcm_eventlog_event_t* zcm_eventlog_read_prev_event(zcm_eventlog_t* eventlog)
    zcm_eventlog_event_t* zcm_eventlog_read_event_at_offset(zcm_eventlog_t* eventlog, off_t offset)
    void                  zcm_eventlog_free_event(zcm_eventlog_event_t* event)
    int                   zcm_eventlog_write_event(zcm_eventlog_t* eventlog, \
                                                   const zcm_eventlog_event_t* event)

cdef class ZCMSubscription:
    cdef zcm_sub_t* sub
    cdef object handler
    cdef object msgtype

cdef void handler_cb(const zcm_recv_buf_t* rbuf, const char* channel, void* usr) with gil:
    subs = (<ZCMSubscription>usr)
    msg = subs.msgtype.decode(rbuf.data[:rbuf.data_size])
    subs.handler(channel, msg)

cdef class ZCM:
    cdef zcm_t* zcm
    def __cinit__(self, bytes url=<bytes>""):
        PyEval_InitThreads()
        self.zcm = zcm_create(url)
    def __dealloc__(self):
        self.stop()
        zcm_destroy(self.zcm)
    def good(self):
        return self.zcm != NULL
    def err(self):
        return zcm_errno(self.zcm)
    def strerror(self):
        return <bytes>zcm_strerror(self.zcm)
    def strerrno(self, err):
        return <bytes>zcm_strerrno(err)
    def subscribe(self, bytes channel, msgtype, handler):
        cdef ZCMSubscription subs = ZCMSubscription()
        subs.handler = handler
        subs.msgtype = msgtype
        while True:
            subs.sub = zcm_try_subscribe(self.zcm, channel, handler_cb, <void*> subs)
            if subs.sub != NULL:
                return subs
            time.sleep(0) # yield the gil
    def unsubscribe(self, ZCMSubscription sub):
        while zcm_try_unsubscribe(self.zcm, sub.sub) != ZCM_EOK:
            time.sleep(0) # yield the gil
    def publish(self, bytes channel, object msg):
        _data = msg.encode()
        cdef const uint8_t* data = _data
        return zcm_publish(self.zcm, channel, data, len(_data) * sizeof(uint8_t))
    def flush(self):
        while zcm_try_flush(self.zcm) != ZCM_EOK:
            time.sleep(0) # yield the gil
    def run(self):
        zcm_run(self.zcm)
    def start(self):
        zcm_start(self.zcm)
    def stop(self):
        while zcm_try_stop(self.zcm) != ZCM_EOK:
            time.sleep(0) # yield the gil
    def pause(self):
        zcm_pause(self.zcm)
    def resume(self):
        zcm_resume(self.zcm)
    def handle(self):
        return zcm_handle(self.zcm)
    def setQueueSize(self, numMsgs):
        while zcm_try_set_queue_size(self.zcm, numMsgs) != ZCM_EOK:
            time.sleep(0) # yield the gil
    def handleNonblock(self):
        return zcm_handle_nonblock(self.zcm)

cdef class LogEvent:
    cdef int64_t eventnum
    cdef int64_t timestamp
    cdef object  channel
    cdef object  data
    def __cinit__(self):
        pass
    def getEventnum(self):
        return self.eventnum
    def setTimestamp(self, int64_t time):
        self.timestamp = time
    def getTimestamp(self):
        return self.timestamp
    def setChannel(self, bytes chan):
        self.channel = chan
    def getChannel(self):
        return self.channel
    def setData(self, bytes data):
        self.data = data
    def getData(self):
        return self.data

cdef class LogFile:
    cdef zcm_eventlog_t* eventlog
    cdef zcm_eventlog_event_t* lastevent
    def __cinit__(self, bytes path, bytes mode):
        self.eventlog = zcm_eventlog_create(path, mode)
        self.lastevent = NULL
    def __dealloc__(self):
        self.close()
    def close(self):
        if self.eventlog != NULL:
            zcm_eventlog_destroy(self.eventlog)
            self.eventlog = NULL
        if self.lastevent != NULL:
            zcm_eventlog_free_event(self.lastevent)
            self.lastevent = NULL
    def good(self):
        return self.eventlog != NULL
    def seekToTimestamp(self, int64_t timestamp):
        return zcm_eventlog_seek_to_timestamp(self.eventlog, timestamp)
    cdef __setCurrentEvent(self, zcm_eventlog_event_t* evt):
        if self.lastevent != NULL:
            zcm_eventlog_free_event(self.lastevent)
        self.lastevent = evt
        cdef LogEvent curEvent = LogEvent()
        if evt == NULL:
            return None
        curEvent.eventnum = evt.eventnum
        curEvent.setChannel   (evt.channel[:evt.channellen])
        curEvent.setTimestamp (evt.timestamp)
        curEvent.setData      ((<uint8_t*>evt.data)[:evt.datalen])
        return curEvent
    def readNextEvent(self):
        cdef zcm_eventlog_event_t* evt = zcm_eventlog_read_next_event(self.eventlog)
        return self.__setCurrentEvent(evt)
    def readPrevEvent(self):
        cdef zcm_eventlog_event_t* evt = zcm_eventlog_read_prev_event(self.eventlog)
        return self.__setCurrentEvent(evt)
    def readEventOffset(self, off_t offset):
        cdef zcm_eventlog_event_t* evt = zcm_eventlog_read_event_at_offset(self.eventlog, offset)
        return self.__setCurrentEvent(evt)
    def writeEvent(self, LogEvent event):
        cdef zcm_eventlog_event_t evt
        evt.eventnum   = event.eventnum
        evt.timestamp  = event.timestamp
        evt.channellen = len(event.channel)
        evt.datalen    = len(event.data)
        evt.channel    = <char*> event.channel
        evt.data       = <uint8_t*> event.data
        return zcm_eventlog_write_event(self.eventlog, &evt);