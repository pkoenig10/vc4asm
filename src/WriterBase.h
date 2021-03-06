/*
 * WriterBase.h
 *
 *  Created on: 02.04.2017
 *      Author: mueller
 */

#ifndef WRITERBASE_H_
#define WRITERBASE_H_

#include "utils.h"

#include <cstdio>
#include <string>
#include <functional>

using namespace std;


// Work around because gcc can't define a constexpr struct inside a class, part 1.
#define MSG WriterMSG
#include "Writer.MSG.h"
#undef MSG

/// Common services for writer classes.
class WriterBase
{public:
	// Work around because gcc can't define a constexpr struct inside a class, part 2.
	//#include "Writer.MSG.h"
	static constexpr const struct WriterMSG MSG = WriterMSG;

 protected:
	FILE* Target;
	WriterBase(FILE* target) : Target(target) {}
	void WriteChar(char c)              { checkedwrite(Target, &c, 1); }
	template <size_t N>
	void WriteString(const char (&str)[N]) { checkedwrite(Target, str, N-1); }
	void WriteString(const string& str) { checkedwrite(Target, str.data(), str.length()); }
	template<typename T>
	void WriteRaw(const T& data)        { checkedwrite(Target, &data, sizeof(data)); }
	void WriteWithTemplate(const char* templname, function<bool(const string&)> atplaceholder);
};

#endif // WRITERBASE_H_
