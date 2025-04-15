#define FDB_API_VERSION 710

#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <fdb_c.h>
#include <unistd.h>

FDBTenant *fdb_tenant = NULL;
FDBTransaction *tr = NULL;
FDBDatabase *db = NULL;
pthread_t netThread;

static void checkError(fdb_error_t errorNum) {
  if (errorNum) {
    fprintf(stderr, "Error (%d): %s\n", errorNum, fdb_get_error(errorNum));
    exit(errorNum);
  }
}

static void waitAndCheckError(FDBFuture *future) {
  checkError(fdb_future_block_until_ready(future));
  if (fdb_future_get_error(future) != 0) {
    checkError(fdb_future_get_error(future));
  }
}

static void runNetwork() { checkError(fdb_run_network()); }

void createDataInDatabase() {
  int committed = 0;
  /*  Create transaction. */
  checkError(fdb_database_create_transaction(db, &tr));

  while (!committed) {
    /* Create data */
    char *key1 = "Test Key1";
    char *val1 = "Test Value1";
    fdb_transaction_set(tr, key1, (int)strlen(key1), val1, (int)strlen(val1));

    /* Commit to database.*/
    FDBFuture *commitFuture = fdb_transaction_commit(tr);
    checkError(fdb_future_block_until_ready(commitFuture));
    if (fdb_future_get_error(commitFuture) != 0) {
      waitAndCheckError(
          fdb_transaction_on_error(tr, fdb_future_get_error(commitFuture)));
    } else {
      committed = 1;
    }
    fdb_future_destroy(commitFuture);
  }
  /* Destroy transaction. */
  fdb_transaction_destroy(tr);
}

void createTenantDataAndReadData() {
  char *tenant_name = "example";
  FDBTransaction *tr = NULL;
  FDBTransaction *tr2 = NULL;
  fdb_bool_t valuePresent;
  int valueLength;
  const uint8_t *value = NULL;
  const char *k1 = "tenant key1";
  const char *v1 = "tenant value1";

  checkError(fdb_database_open_tenant(db, (uint8_t const *)tenant_name,
                                      strlen(tenant_name), &fdb_tenant));
  checkError(fdb_tenant_create_transaction(fdb_tenant, &tr));
  fdb_transaction_set(tr, k1, (int)strlen(k1), v1, (int)strlen(v1));
  FDBFuture *commitFuture = fdb_transaction_commit(tr);
  checkError(fdb_future_block_until_ready(commitFuture));
  if (fdb_future_get_error(commitFuture) != 0) {
    waitAndCheckError(
        fdb_transaction_on_error(tr, fdb_future_get_error(commitFuture)));
  }
  fdb_transaction_destroy(tr);
  fdb_future_destroy(commitFuture);

  checkError(fdb_tenant_create_transaction(fdb_tenant, &tr2));
  FDBFuture *getFuture = fdb_transaction_get(tr2, k1, (int)strlen(k1), 0);
  waitAndCheckError(getFuture);
  checkError(
      fdb_future_get_value(getFuture, &valuePresent, &value, &valueLength));

  printf("Get value from tenant , key : %s, value : %s, value-len : %d\n", k1,
         value, valueLength);
  fdb_transaction_destroy(tr2);
  fdb_future_destroy(getFuture);
}

void readDataFromDatabase() {
  FDBTransaction *tr = NULL;
  const uint8_t *value = NULL;
  fdb_bool_t valuePresent;
  int valueLength;
  char *key = "Test Key1";

  checkError(fdb_database_create_transaction(db, &tr));
  FDBFuture *getFuture = fdb_transaction_get(tr, key, (int)strlen(key), 0);
  waitAndCheckError(getFuture);

  checkError(
      fdb_future_get_value(getFuture, &valuePresent, &value, &valueLength));

  printf("Got Value from db. %s: '%.*s'\n", key, valueLength, value);
  fdb_transaction_destroy(tr);
  fdb_future_destroy(getFuture);
}

int main() {
  /* Default fdb cluster file. */
  char *cluster_file = "/etc/foundationdb/fdb.cluster";

  /* Setup network. */
  checkError(fdb_select_api_version(FDB_API_VERSION));
  checkError(fdb_setup_network());
  puts("Created network.");

  pthread_create(&netThread, NULL, (void *)runNetwork, NULL);

  checkError(fdb_create_database(cluster_file, &db));
  puts("Created database.");

  /*Create tenant and do nothing.*/
  createDataInDatabase();
  readDataFromDatabase();

  createTenantDataAndReadData();

  puts("Program done. Now exiting...");
  fdb_tenant_destroy(fdb_tenant);
  fdb_tenant = NULL;
  fdb_database_destroy(db);
  db = NULL;
  checkError(fdb_stop_network());
  int rc = pthread_join(netThread, NULL);
  if (rc)
    fprintf(stderr, "ERROR: network thread failed to join\n");
  exit(0);
}
