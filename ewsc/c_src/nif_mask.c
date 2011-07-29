#include "erl_nif.h" 
 
void mask(unsigned char *key, unsigned char *data, unsigned long len)
{
    unsigned int *p = (unsigned int *)data;
    unsigned int *k = (unsigned int *)key;
    for(int i=4; i<len; i+=4)
    {
	*(p+(i-4)/4) ^= *k;
    }

    int r = len % 4;
    if (r)
    {
	for(int i=0; i<r; i++)
	{
	    data[len-r+i] ^= key[i];
	}
    }
}
/*
 * Erlang call would be like
 * nif_mask(Key, Data,Len)
 * where Key is 4 bytes binary
 *       Data is binary with length Len
 */
static ERL_NIF_TERM nif_mask(ErlNifEnv* env,int argc, const ERL_NIF_TERM argv[]) { 
    ErlNifBinary data, key;
    enif_inspect_binary(env, argv[0], &key);
    enif_inspect_binary(env, argv[1], &data);
    enif_realloc_binary(&data, data.size);
    mask(key.data,data.data, data.size);
    return enif_make_binary(env, &data);
} 
 
static ErlNifFunc nif_funcs[] = { 
  {"nif_mask", 3, nif_mask} 
  }; 
 
ERL_NIF_INIT(websocket_client,nif_funcs,NULL,NULL,NULL,NULL); 
