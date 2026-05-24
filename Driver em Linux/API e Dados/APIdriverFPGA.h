#include <stdint.h>
#ifndef API_DRIVERFPGA
#define API_DRIVERFPGA

/*Rotina em Assembly para pegar o endereço base da FPGA
* @return Ponteiro para o endereço base da memória da FPGA (mapeada em I/O)
*/
volatile uint32_t* inicializar_hardware(void);

/*Rotina em Assembly para enviar a imagem para o coprocessador
* @param Ponteiro para o endereço base da memória da FPGA (mapeada em I/O)
* @param Ponteiro para o endereço base do vetor da imagem
*/
void enviarImagem(volatile uint32_t *base,const uint8_t *buffer);

/*Rotina em Assembly para enviar o W_in para o coprocessador
* @param Ponteiro para o endereço base da memória da FPGA (mapeada em I/O)
* @param Ponteiro para o endereço base do vetor do W_in
*/
void enviarPesos(volatile uint32_t *base,const uint16_t *buffer);

/*Rotina em Assembly para enviar o bias para o coprocessador
* @param Ponteiro para o endereço base da memória da FPGA (mapeada em I/O)
* @param Ponteiro para o endereço base do vetor do bias
*/
void enviarBias(volatile uint32_t *base,const uint16_t *buffer);

/*Rotina em Assembly para enviar o beta para o coprocessador
* @param Ponteiro para o endereço base da memória da FPGA (mapeada em I/O)
* @param Ponteiro para o endereço base do vetor do beta
*/
void enviarBeta(volatile uint32_t *base,const uint16_t *buffer);

/*Rotina em Assembly para iniciar a inferência no coprocessador
* @param Ponteiro para o endereço base da memória da FPGA (mapeada em I/O)
*/
int iniciar_inferencia(volatile uint32_t *base);

/*Rotina em Assembly para resetar o coprocessador
* @param Ponteiro para o endereço base da memória da FPGA (mapeada em I/O)
*/
void resetar_fpga(volatile uint32_t *base);

/*Rotina em Assembly para limpar as flags error e done do coprocessador
* @param Ponteiro para o endereço base da memória da FPGA (mapeada em I/O)
*/
void clear_fpga(volatile uint32_t *base);

#endif