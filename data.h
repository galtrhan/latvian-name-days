#ifndef LND_DATA_H
#define LND_DATA_H

#include <stddef.h>
#include <stdint.h>

typedef struct {
	uint8_t month;
	uint8_t day;
	const char *names;
} Entry;

extern const Entry EMBEDDED_ENTRIES[];
extern const size_t EMBEDDED_ENTRIES_COUNT;

#endif
