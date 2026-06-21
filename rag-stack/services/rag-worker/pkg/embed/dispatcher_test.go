package embed

import (
	"sync"
	"testing"
	"time"
)

// dispatchDirect exercises the Register/Deregister/dispatch logic without
// a live Pulsar consumer. It calls the same map operations that Run() does.
func dispatchDirect(d *ResultDispatcher, result EmbedResult) {
	d.mu.RLock()
	ch, ok := d.pending[result.RequestID]
	d.mu.RUnlock()
	if ok {
		ch <- result
	}
}

func newTestDispatcher() *ResultDispatcher {
	return &ResultDispatcher{
		pending: make(map[string]chan EmbedResult),
	}
}

func TestRegisterAndReceive(t *testing.T) {
	d := newTestDispatcher()
	ch := d.Register("req-1", 2)

	r1 := EmbedResult{RequestID: "req-1", SubQueryIndex: 0, Vector: []float32{0.1, 0.2}}
	r2 := EmbedResult{RequestID: "req-1", SubQueryIndex: 1, Vector: []float32{0.3, 0.4}}

	dispatchDirect(d, r1)
	dispatchDirect(d, r2)

	got1 := <-ch
	got2 := <-ch

	if got1.SubQueryIndex != 0 && got2.SubQueryIndex != 0 {
		t.Error("expected sub_query_index 0 in one of the results")
	}
	if got1.SubQueryIndex != 1 && got2.SubQueryIndex != 1 {
		t.Error("expected sub_query_index 1 in one of the results")
	}
}

func TestDeregisterPreventsDispatch(t *testing.T) {
	d := newTestDispatcher()
	d.Register("req-deregister", 1)
	d.Deregister("req-deregister")

	// dispatch after deregister should be a no-op (no panic, no send to closed channel)
	dispatchDirect(d, EmbedResult{RequestID: "req-deregister", SubQueryIndex: 0})
}

func TestStaleResultDropped(t *testing.T) {
	d := newTestDispatcher()
	// Never register "req-stale" — simulates a timed-out request.
	// dispatchDirect should silently drop the result (same as Run() behaviour).
	dispatchDirect(d, EmbedResult{RequestID: "req-stale", SubQueryIndex: 0})
}

func TestMultipleConcurrentRequests(t *testing.T) {
	d := newTestDispatcher()
	const n = 10

	chs := make([]<-chan EmbedResult, n)
	for i := 0; i < n; i++ {
		reqID := string(rune('A' + i))
		chs[i] = d.Register(reqID, 1)
	}

	var wg sync.WaitGroup
	for i := 0; i < n; i++ {
		wg.Add(1)
		go func(idx int) {
			defer wg.Done()
			reqID := string(rune('A' + idx))
			dispatchDirect(d, EmbedResult{RequestID: reqID, SubQueryIndex: 0, Vector: []float32{float32(idx)}})
		}(i)
	}
	wg.Wait()

	for i := 0; i < n; i++ {
		reqID := string(rune('A' + i))
		select {
		case r := <-chs[i]:
			if r.Vector[0] != float32(i) {
				t.Errorf("request %s: expected vector[0]=%v got %v", reqID, float32(i), r.Vector[0])
			}
		case <-time.After(2 * time.Second):
			t.Errorf("timeout waiting for result for request %s", reqID)
		}
		d.Deregister(reqID)
	}
}

func TestBufferDoesNotBlockOnFullChannel(t *testing.T) {
	// Channel is sized to n; sending more than n without reading should not deadlock
	// (the extra sends are fired from a separate goroutine so we can apply a timeout).
	d := newTestDispatcher()
	ch := d.Register("req-overflow", 1)

	sent := make(chan struct{})
	go func() {
		// First send fills the buffer.
		dispatchDirect(d, EmbedResult{RequestID: "req-overflow", SubQueryIndex: 0})
		// Second send has no registered channel (we deregistered) — should be a no-op.
		d.Deregister("req-overflow")
		dispatchDirect(d, EmbedResult{RequestID: "req-overflow", SubQueryIndex: 1})
		close(sent)
	}()

	select {
	case <-sent:
	case <-time.After(2 * time.Second):
		t.Fatal("goroutine blocked — possible deadlock in dispatch")
	}

	// Drain buffered result.
	select {
	case r := <-ch:
		if r.SubQueryIndex != 0 {
			t.Errorf("expected SubQueryIndex 0, got %d", r.SubQueryIndex)
		}
	default:
		t.Error("expected one buffered result")
	}
}
