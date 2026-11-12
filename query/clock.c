#include <stdint.h>
#include <time.h>

int moonbean_local_date(int64_t timestamp) {
  time_t seconds = (time_t)timestamp;
  struct tm local;
#ifdef _WIN32
  if (localtime_s(&local, &seconds) != 0) return 0;
#else
  if (localtime_r(&seconds, &local) == NULL) return 0;
#endif
  return (local.tm_year + 1900) * 10000 + (local.tm_mon + 1) * 100 + local.tm_mday;
}
