CC ?= cc
CFLAGS ?= -O2 -g -Wall -Wextra -Werror -std=c99 -D_GNU_SOURCE -DQMODEM_HOST_TEST
SRC := ../src
TIMEOUT ?= timeout 10s

.PHONY: all baseline clean

all: baseline test_terminal_matching test_line_event_queue test_reader_flood test_port_lifecycle \
	test_port_concurrency test_production_reader_lifecycle test_uloop_adapter
	$(TIMEOUT) ./test_terminal_matching
	$(TIMEOUT) ./test_line_event_queue
	$(TIMEOUT) ./test_reader_flood
	$(TIMEOUT) ./test_port_lifecycle
	$(TIMEOUT) ./test_port_concurrency
	$(TIMEOUT) ./test_production_reader_lifecycle
	$(TIMEOUT) ./test_uloop_adapter

baseline: test_response_baseline
	$(TIMEOUT) ./test_response_baseline

test_response_baseline: test_response_baseline.c $(SRC)/at_handler.c $(SRC)/line_events.c
	$(CC) $(CFLAGS) -I$(SRC) $^ -o $@ -pthread -lutil

test_terminal_matching: test_terminal_matching.c $(SRC)/at_handler.c $(SRC)/line_events.c
	$(CC) $(CFLAGS) -I$(SRC) $^ -o $@ -pthread -lutil

test_line_event_queue: test_line_event_queue.c $(SRC)/line_events.c
	$(CC) $(CFLAGS) -I$(SRC) $^ -o $@ -pthread

test_reader_flood: test_reader_flood.c $(SRC)/at_handler.c $(SRC)/line_events.c
	$(CC) $(CFLAGS) -I$(SRC) $^ -o $@ -pthread -lutil

test_port_lifecycle: test_port_lifecycle.c $(SRC)/port_manager.c
	$(CC) $(CFLAGS) -I$(SRC) $^ -o $@ -pthread -lutil

test_port_concurrency: test_port_concurrency.c $(SRC)/port_manager.c $(SRC)/line_events.c
	$(CC) $(CFLAGS) -I$(SRC) $^ -o $@ -pthread

test_production_reader_lifecycle: test_production_reader_lifecycle.c $(SRC)/port_manager.c \
		$(SRC)/at_handler.c $(SRC)/line_events.c
	$(CC) $(CFLAGS) -I$(SRC) $^ -o $@ -pthread -lutil \
		-Wl,--wrap=pthread_mutex_lock -Wl,--wrap=pthread_join

test_uloop_adapter: test_uloop_adapter.c
	$(CC) $(filter-out -DQMODEM_HOST_TEST,$(CFLAGS)) -Wno-unused-function \
		-Ifakes -I$(SRC) $< -o $@ -pthread

clean:
	rm -f test_response_baseline test_terminal_matching test_line_event_queue test_reader_flood \
		test_port_lifecycle test_port_concurrency test_production_reader_lifecycle test_uloop_adapter
