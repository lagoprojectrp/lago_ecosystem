#include "bmp180.h"

/* Lookup table for BMP180 register addresses */
int32_t bmp180_register_table[11][2] = 
{
    {BMP180_REG_AC1_H, 1},
    {BMP180_REG_AC2_H, 1},
    {BMP180_REG_AC3_H, 1},
    {BMP180_REG_AC4_H, 0},
    {BMP180_REG_AC5_H, 0},
    {BMP180_REG_AC6_H, 0},
    {BMP180_REG_B1_H, 1},
    {BMP180_REG_B2_H, 1},
    {BMP180_REG_MB_H, 1},
    {BMP180_REG_MC_H, 1},
    {BMP180_REG_MD_H, 1}
};

/*
 * Returns the raw measured temperature value of this BMP180 sensor.
 * 
 * @param bmp180 sensor
 */
static int32_t bmp180_read_raw_temperature(void *_bmp) 
{
	bmp180_t* bmp = TO_BMP(_bmp);
	i2c_smbus_write_byte_data(bmp->file, BMP180_CTRL, BMP180_TMP_READ_CMD);

	usleep(BMP180_TMP_READ_WAIT_US);
	int32_t data = i2c_smbus_read_word_data(bmp->file, BMP180_REG_TMP) & 0xFFFF;
	
	data = ((data << 8) & 0xFF00) + (data >> 8);
	
	return data;
}

/*
 * Returns the raw measured pressure value of this BMP180 sensor.
 * 
 * @param bmp180 sensor
 */
static int32_t bmp180_read_raw_pressure(void *_bmp, uint8_t oss) 
{
	bmp180_t* bmp = TO_BMP(_bmp);
	uint16_t wait;
	uint8_t cmd;
	
	switch(oss) {
		case BMP180_PRE_OSS1:
			wait = BMP180_PRE_OSS1_WAIT_US; cmd = BMP180_PRE_OSS1_CMD;
			break;
		
		case BMP180_PRE_OSS2:
			wait = BMP180_PRE_OSS2_WAIT_US; cmd = BMP180_PRE_OSS2_CMD;
			break;
		
		case BMP180_PRE_OSS3:
			wait = BMP180_PRE_OSS3_WAIT_US; cmd = BMP180_PRE_OSS3_CMD;
			break;
		
		case BMP180_PRE_OSS0:
		default:
			wait = BMP180_PRE_OSS0_WAIT_US; cmd = BMP180_PRE_OSS0_CMD;
			break;
	}
	
	i2c_smbus_write_byte_data(bmp->file, BMP180_CTRL, cmd);

	usleep(wait);
	
	int32_t msb, lsb, xlsb, data;
	msb = i2c_smbus_read_byte_data(bmp->file, BMP180_REG_PRE) & 0xFF;
	lsb = i2c_smbus_read_byte_data(bmp->file, BMP180_REG_PRE+1) & 0xFF;
	xlsb = i2c_smbus_read_byte_data(bmp->file, BMP180_REG_PRE+2) & 0xFF;
	
	data = ((msb << 16)  + (lsb << 8)  + xlsb) >> (8 - bmp->oss);
	
	return data;
}

/**
 * Returns the measured pressure in pascal.
 * 
 * @param bmp180 sensor
 * @return pressure
 */
static long bmp180_pressure(void *_bmp) 
{
	bmp180_t* bmp = TO_BMP(_bmp);
	long UT, UP, B6, B5, X1, X2, X3, B3, p;
	unsigned long B4, B7;
	
	UT = bmp180_read_raw_temperature(_bmp);
	UP = bmp180_read_raw_pressure(_bmp, bmp->oss);
	
	X1 = ((UT - bmp->ac6) * bmp->ac5) >> 15;
	X2 = (bmp->mc << 11) / (X1 + bmp->md);
	
	B5 = X1 + X2;
	
	B6 = B5 - 4000;
	
	X1 = (bmp->b2 * (B6 * B6) >> 12) >> 11;
	X2 = (bmp->ac2 * B6) >> 11;
	X3 = X1 + X2;
	
	B3 = ((((bmp->ac1 * 4) + X3) << bmp->oss) + 2) / 4;
	X1 = (bmp->ac3 * B6) >> 13;
	X2 = (bmp->b1 * ((B6 * B6) >> 12)) >> 16;
	X3 = ((X1 + X2) + 2) >> 2;
	
	
	B4 = bmp->ac4 * (unsigned long)(X3 + 32768) >> 15;
	B7 = ((unsigned long) UP - B3) * (50000 >> bmp->oss);
	
	if(B7 < 0x80000000) {
		p = (B7 * 2) / B4;
	} else {
		p = (B7 / B4) * 2;
	}
	
	X1 = (p >> 8) * (p >> 8);
	X1 = (X1 * 3038) >> 16;
	X2 = (-7357 * p) >> 16;
	p = p + ((X1 + X2 + 3791) >> 4);
	
	return p;
}

/*
 * Sets the address for the i2c device file.
 * 
 * @param bmp180 sensor
 */
static int bmp180_set_addr(void *_bmp) 
{
	bmp180_t* bmp = TO_BMP(_bmp);
	int error;

	if((error = ioctl(bmp->file, I2C_SLAVE, bmp->address)) < 0) {
		DEBUG("error: ioctl() failed\n");
	}

	return error;
}

/*
 * Frees allocated memory in the init function.
 * 
 * @param bmp180 sensor
 */
static void bmp180_init_error_cleanup(void *_bmp) 
{
	bmp180_t* bmp = TO_BMP(_bmp);
	
	if(bmp->i2c_device != NULL) {
		free(bmp->i2c_device);
		bmp->i2c_device = NULL;
	}
	
	free(bmp);
	bmp = NULL;
}

/*
 * Reads a single calibration coefficient from the BMP180 eprom.
 * 
 * @param bmp180 sensor
 */
static void bmp180_read_eprom_reg(void *_bmp, int32_t *_store, uint8_t reg, int32_t sign) 
{
	bmp180_t *bmp = TO_BMP(_bmp);
	int32_t data = i2c_smbus_read_word_data(bmp->file, reg) & 0xFFFF;
	
	// i2c_smbus_read_word_data assumes little endian 
	// but ARM uses big endian. Thus the ordering of the bytes is reversed.
	// data = 	 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15   bit position
	//          |      lsb      |          msb        |  
	
	//                 msb           +     lsb
	*_store = ((data << 8) & 0xFF00) + (data >> 8);
	
	if(sign && (*_store > 32767)) {
		*_store -= 65536;
	}
}

/*
 * Reads the eprom of this BMP180 sensor.
 * 
 * @param bmp180 sensor
 */
void bmp180_read_eprom(void *_bmp) 
{
	bmp180_t *bmp = TO_BMP(_bmp);	
	
	int32_t *bmp180_register_addr[11] = {
		&bmp->ac1, &bmp->ac2, &bmp->ac3, &bmp->ac4, &bmp->ac5, &bmp->ac6,
		&bmp->b1, &bmp->b2, &bmp->mb, &bmp->mc, &bmp->md
	};
	
	uint8_t sign, reg;
	int32_t *data;
	int i;
	for(i = 0; i < 11; i++) {
		reg = (uint8_t) bmp180_register_table[i][0];
		sign = (uint8_t) bmp180_register_table[i][1];
		data = bmp180_register_addr[i];
		bmp180_read_eprom_reg(_bmp, data, reg, sign);
	}
}

/**
 * Dumps the eprom values of this BMP180 sensor.
 * 
 * @param bmp180 sensor
 * @param bmp180 eprom struct
 */
void bmp180_dump_eprom(void *_bmp, bmp180_eprom_t *eprom) 
{
	bmp180_t *bmp = TO_BMP(_bmp);
	eprom->ac1 = bmp->ac1;
	eprom->ac2 = bmp->ac2;
	eprom->ac3 = bmp->ac3;
	eprom->ac4 = bmp->ac4;
	eprom->ac5 = bmp->ac5;
	eprom->ac6 = bmp->ac6;
	eprom->b1 = bmp->b1;
	eprom->b2 = bmp->b2;
	eprom->mb = bmp->mb;
	eprom->mc = bmp->mc;
	eprom->md = bmp->md;
}

/**
 * Creates a BMP180 sensor object.
 *
 * @param i2c device address
 * @param i2c device file path
 * @return bmp180 sensor
 */
void *bmp180_init(int address, const char* i2c_device_filepath) 
{
	DEBUG("device: init using address %#x and i2cbus %s\n", address, i2c_device_filepath);
	
	// setup BMP180
	void *_bmp = malloc(sizeof(bmp180_t));
	if(_bmp == NULL)  {
		DEBUG("error: malloc returns NULL pointer\n");
		return NULL;
	}

	bmp180_t *bmp = TO_BMP(_bmp);
	bmp->address = address;

	// setup i2c device path
	bmp->i2c_device = (char*) malloc(strlen(i2c_device_filepath) * sizeof(char));
	if(bmp->i2c_device == NULL) {
		DEBUG("error: malloc returns NULL pointer!\n");
		bmp180_init_error_cleanup(bmp);
		return NULL;
	}

	// copy string
	strcpy(bmp->i2c_device, i2c_device_filepath);
	
	// open i2c device
	int file;
	if((file = open(bmp->i2c_device, O_RDWR)) < 0) {
		DEBUG("error: %s open() failed\n", bmp->i2c_device);
		bmp180_init_error_cleanup(bmp);
		return NULL;
	}
	bmp->file = file;

	// set i2c device address
	if(bmp180_set_addr(_bmp) < 0) {
		bmp180_init_error_cleanup(bmp);
		return NULL;
	}

	// setup i2c device
	bmp180_read_eprom(_bmp);
	bmp->oss = 0;
	
	DEBUG("device: open ok\n");

	return _bmp;
}

/**
 * Closes a BMP180 object.
 * 
 * @param bmp180 sensor
 */
void bmp180_close(void *_bmp) 
{
	if(_bmp == NULL) {
		return;
	}
	
	DEBUG("close bmp180 device\n");
	bmp180_t *bmp = TO_BMP(_bmp);
	
	if(close(bmp->file) < 0) {
		DEBUG("error: %s close() failed\n", bmp->i2c_device);
	}
	
	free(bmp->i2c_device); // free string
	bmp->i2c_device = NULL;
	free(bmp); // free bmp structure
	_bmp = NULL;
} 

/**
 * Returns the measured temperature in celsius.
 * 
 * @param bmp180 sensor
 * @return temperature
 */
float bmp180_temperature(void *_bmp) 
{
	bmp180_t* bmp = TO_BMP(_bmp);
	long UT, X1, X2, B5;
	float T;
	
	UT = bmp180_read_raw_temperature(_bmp);
	
	DEBUG("UT=%lu\n",UT);
	
	X1 = ((UT - bmp->ac6) * bmp->ac5) >> 15;
	X2 = (bmp->mc << 11) / (X1 + bmp->md);
	B5 = X1 + X2;
	T = ((B5 + 8) >> 4) / 10.0;
	
	return T;
}

/**
 * Returns altitude in meters based on the measured pressure 
 * and temperature of this sensor.
 * 
 * @param bmp180 sensor
 * @return altitude
 */
float bmp180_altitude(void *_bmp) 
{
	float p, alt;
	p = bmp180_pressure(_bmp);
	alt = 44330 * (1 - pow(( (p/100) / BMP180_SEA_LEVEL),1/5.255));
	
	return alt;
}

/**
 * Sets the oversampling setting for this sensor.
 * 
 * @param bmp180 sensor
 * @param oversampling mode
 */
void bmp180_set_oss(void *_bmp, int oss) 
{
	bmp180_t* bmp = TO_BMP(_bmp);
	bmp->oss = oss;
}

