// android/app/src/main/cpp/LiveProg.cpp
#include "LiveProg.h"
#include <cmath>
#include <cctype>
#include <cstdlib>
#include <algorithm>
#include <sstream>

namespace {

enum class TokenType {
    End,
    Number,
    Ident,
    Plus,
    Minus,
    Mul,
    Div,
    Mod,
    Assign,
    Eq,
    Neq,
    Lt,
    Lte,
    Gt,
    Gte,
    LParen,
    RParen,
    LBrace,
    RBrace,
    Comma,
    Semi,
    Question,
    Colon,
    AtInit,
    AtSample,
    If,
    Else
};

struct Token {
    TokenType type = TokenType::End;
    double numVal = 0.0;
    std::string strVal;
};

class Lexer {
public:
    explicit Lexer(const std::string& src) : src_(src), pos_(0) {}

    Token peek() {
        size_t savePos = pos_;
        Token t = next();
        pos_ = savePos;
        return t;
    }

    Token next() {
        skipWhitespace();
        if (pos_ >= src_.size()) return {TokenType::End, 0.0, ""};

        char c = src_[pos_];

        if (c == '@') {
            size_t start = pos_;
            while (pos_ < src_.size() && std::isalpha(src_[pos_])) ++pos_;
            std::string tag = src_.substr(start, pos_ - start);
            if (tag == "@init") return {TokenType::AtInit, 0.0, tag};
            if (tag == "@sample") return {TokenType::AtSample, 0.0, tag};
            return {TokenType::Ident, 0.0, tag};
        }

        if (std::isalpha(c) || c == '_') {
            size_t start = pos_;
            while (pos_ < src_.size() && (std::isalnum(src_[pos_]) || src_[pos_] == '_')) ++pos_;
            std::string ident = src_.substr(start, pos_ - start);
            if (ident == "if") return {TokenType::If, 0.0, ident};
            if (ident == "else") return {TokenType::Else, 0.0, ident};
            return {TokenType::Ident, 0.0, ident};
        }

        if (std::isdigit(c) || (c == '.' && pos_ + 1 < src_.size() && std::isdigit(src_[pos_ + 1]))) {
            size_t start = pos_;
            while (pos_ < src_.size() && (std::isdigit(src_[pos_]) || src_[pos_] == '.' || src_[pos_] == 'e' || src_[pos_] == 'E')) {
                if ((src_[pos_] == 'e' || src_[pos_] == 'E') && pos_ + 1 < src_.size() && (src_[pos_ + 1] == '+' || src_[pos_ + 1] == '-')) {
                    pos_ += 2;
                } else {
                    ++pos_;
                }
            }
            double val = std::strtod(src_.c_str() + start, nullptr);
            return {TokenType::Number, val, ""};
        }

        ++pos_;
        switch (c) {
            case '+': return {TokenType::Plus, 0.0, "+"};
            case '-': return {TokenType::Minus, 0.0, "-"};
            case '*': return {TokenType::Mul, 0.0, "*"};
            case '/': return {TokenType::Div, 0.0, "/"};
            case '%': return {TokenType::Mod, 0.0, "%"};
            case '(': return {TokenType::LParen, 0.0, "("};
            case ')': return {TokenType::RParen, 0.0, ")"};
            case '{': return {TokenType::LBrace, 0.0, "{"};
            case '}': return {TokenType::RBrace, 0.0, "}"};
            case ',': return {TokenType::Comma, 0.0, ","};
            case ';': return {TokenType::Semi, 0.0, ";"};
            case '?': return {TokenType::Question, 0.0, "?"};
            case ':': return {TokenType::Colon, 0.0, ":"};
            case '=':
                if (pos_ < src_.size() && src_[pos_] == '=') { ++pos_; return {TokenType::Eq, 0.0, "=="}; }
                return {TokenType::Assign, 0.0, "="};
            case '!':
                if (pos_ < src_.size() && src_[pos_] == '=') { ++pos_; return {TokenType::Neq, 0.0, "!="}; }
                break;
            case '<':
                if (pos_ < src_.size() && src_[pos_] == '=') { ++pos_; return {TokenType::Lte, 0.0, "<="}; }
                return {TokenType::Lt, 0.0, "<"};
            case '>':
                if (pos_ < src_.size() && src_[pos_] == '=') { ++pos_; return {TokenType::Gte, 0.0, ">="}; }
                return {TokenType::Gt, 0.0, ">"};
            default: break;
        }

        return {TokenType::End, 0.0, ""};
    }

private:
    void skipWhitespace() {
        while (pos_ < src_.size()) {
            if (std::isspace(src_[pos_])) {
                ++pos_;
            } else if (src_[pos_] == '/' && pos_ + 1 < src_.size() && src_[pos_ + 1] == '/') {
                pos_ += 2;
                while (pos_ < src_.size() && src_[pos_] != '\n') ++pos_;
            } else if (src_[pos_] == '/' && pos_ + 1 < src_.size() && src_[pos_ + 1] == '*') {
                pos_ += 2;
                while (pos_ + 1 < src_.size() && !(src_[pos_] == '*' && src_[pos_ + 1] == '/')) ++pos_;
                pos_ += 2;
            } else {
                break;
            }
        }
    }

    const std::string& src_;
    size_t pos_;
};

int getFunctionId(const std::string& name) {
    if (name == "sin") return 0;
    if (name == "cos") return 1;
    if (name == "tan") return 2;
    if (name == "exp") return 3;
    if (name == "log") return 4;
    if (name == "sqrt") return 5;
    if (name == "abs") return 6;
    if (name == "min") return 7;
    if (name == "max") return 8;
    if (name == "pow") return 9;
    if (name == "floor") return 10;
    if (name == "ceil") return 11;
    if (name == "rand") return 12;
    return -1;
}

// Expected argument count for each builtin. min/max/pow take exactly two; rand
// takes none; the rest take one. Validating arity at compile time prevents the
// interpreter from silently leaving operands on the stack (e.g. min(a,b,c)
// previously stranded `a` and corrupted every subsequent read).
int functionArity(int funcId) {
    switch (funcId) {
        case 7:  // min
        case 8:  // max
        case 9:  // pow
            return 2;
        case 12: // rand
            return 0;
        default:
            return 1;
    }
}
} // namespace

LiveProg::LiveProg() {
    initBytecode_.reserve(MAX_BYTECODE);
    sampleBytecode_.reserve(MAX_BYTECODE);
    memory_.reserve(MAX_MEMORY);
    idxSpl0_ = getOrRegisterVar("spl0");
    idxSpl1_ = getOrRegisterVar("spl1");
    idxSrate_ = getOrRegisterVar("srate");
    for (int i = 0; i < 8; ++i) {
        idxSliders_[i] = getOrRegisterVar("slider" + std::to_string(i + 1));
    }
    setSampleRate(48000.0);
    reset();
}

void LiveProg::setSampleRate(double sampleRate) {
    sampleRate_ = sampleRate;
    if (idxSrate_ >= 0 && idxSrate_ < static_cast<int>(memory_.size())) {
        memory_[idxSrate_] = sampleRate_;
    }
}

int LiveProg::getOrRegisterVar(const std::string& name) {
    auto it = varMap_.find(name);
    if (it != varMap_.end()) return it->second;
    if (static_cast<int>(memory_.size()) >= MAX_MEMORY) return -1;
    int idx = static_cast<int>(memory_.size());
    memory_.push_back(0.0);
    varMap_[name] = idx;
    return idx;
}

void LiveProg::reset() {
    for (size_t i = 0; i < memory_.size(); ++i) {
        if (static_cast<int>(i) != idxSrate_) {
            memory_[i] = 0.0;
        }
    }
    if (idxSrate_ >= 0 && idxSrate_ < static_cast<int>(memory_.size())) {
        memory_[idxSrate_] = sampleRate_;
    }
    if (!initBytecode_.empty()) {
        executeBytecode(initBytecode_);
    }
}

void LiveProg::setSlider(int index, double value) {
    if (index >= 1 && index <= 8) {
        int vIdx = idxSliders_[index - 1];
        if (vIdx >= 0 && vIdx < static_cast<int>(memory_.size())) {
            memory_[vIdx] = value;
        }
    }
}

double LiveProg::getSlider(int index) const {
    if (index >= 1 && index <= 8) {
        int vIdx = idxSliders_[index - 1];
        if (vIdx >= 0 && vIdx < static_cast<int>(memory_.size())) {
            return memory_[vIdx];
        }
    }
    return 0.0;
}

void LiveProg::applyParams(const LiveProgParamSet& params) {
    enabled_ = params.enabled;
    setSlider(1, params.slider1);
    setSlider(2, params.slider2);
    setSlider(3, params.slider3);
    setSlider(4, params.slider4);
    setSlider(5, params.slider5);
    setSlider(6, params.slider6);
    setSlider(7, params.slider7);
    setSlider(8, params.slider8);
    // Preferred path: the script was compiled off the audio thread and packaged
    // into the snapshot. Applying it only copies bytecode (pre-reserved) and
    // resizes pre-reserved memory, so the audio callback never compiles/allocates.
    if (params.program) {
        if (params.program != activeProgram_) {
            loadedCode_ = params.code;
            applyPreparedProgram(params.program);
        }
        return;
    }
    // Never compile on the audio thread — compilation involves heap allocations,
    // string parsing, and hash map lookups that violate real-time constraints.
    // The control thread must always pre-compile via buildProgram().
    // if (!params.code.empty() && params.code != loadedCode_) {
    //     loadCode(params.code);
    // }
}

std::shared_ptr<const LiveProgProgram> LiveProg::buildProgram() const {
    auto p = std::make_shared<LiveProgProgram>();
    p->initBytecode.reserve(initBytecode_.size());
    for (const auto& i : initBytecode_) {
        p->initBytecode.push_back(
            {static_cast<int>(i.op), i.immValue, i.varIndex, i.targetPc, i.funcId});
    }
    p->sampleBytecode.reserve(sampleBytecode_.size());
    for (const auto& i : sampleBytecode_) {
        p->sampleBytecode.push_back(
            {static_cast<int>(i.op), i.immValue, i.varIndex, i.targetPc, i.funcId});
    }
    p->memorySlots = static_cast<int>(memory_.size());
    p->idxSpl0 = idxSpl0_;
    p->idxSpl1 = idxSpl1_;
    p->idxSrate = idxSrate_;
    for (int i = 0; i < 8; ++i) p->idxSliders[i] = idxSliders_[i];
    return p;
}

void LiveProg::applyPreparedProgram(const std::shared_ptr<const LiveProgProgram>& program) {
    if (!program) return;
    activeProgram_ = program;

    initBytecode_.clear();
    for (const auto& i : program->initBytecode) {
        initBytecode_.push_back(
            {static_cast<OpCode>(i.op), i.immValue, i.varIndex, i.targetPc, i.funcId});
    }
    sampleBytecode_.clear();
    for (const auto& i : program->sampleBytecode) {
        sampleBytecode_.push_back(
            {static_cast<OpCode>(i.op), i.immValue, i.varIndex, i.targetPc, i.funcId});
    }

    idxSpl0_ = program->idxSpl0;
    idxSpl1_ = program->idxSpl1;
    idxSrate_ = program->idxSrate;
    for (int i = 0; i < 8; ++i) idxSliders_[i] = program->idxSliders[i];

    const int slots = std::min(program->memorySlots, MAX_MEMORY);
    if (static_cast<int>(memory_.size()) != slots) {
        memory_.resize(slots, 0.0); // capacity pre-reserved -> no allocation
    }

    isCompiled_ = !sampleBytecode_.empty();
    reset();
}

bool LiveProg::loadCode(const std::string& scriptCode) {
    loadedCode_ = scriptCode;
    initBytecode_.clear();
    sampleBytecode_.clear();
    isCompiled_ = false;
    lastError_.clear();

    if (scriptCode.empty()) return true;

    bool ok = compileScript(scriptCode);
    if (ok) {
        isCompiled_ = true;
        activeProgram_ = buildProgram();
        reset();
    }
    return ok;
}

bool LiveProg::compileScript(const std::string& code) {
    // Split into @init and @sample text
    std::string initText;
    std::string sampleText;

    auto pInit = code.find("@init");
    auto pSample = code.find("@sample");

    if (pInit == std::string::npos && pSample == std::string::npos) {
        sampleText = code;
    } else {
        if (pInit != std::string::npos) {
            size_t end = (pSample != std::string::npos && pSample > pInit) ? pSample : code.size();
            initText = code.substr(pInit + 5, end - (pInit + 5));
        }
        if (pSample != std::string::npos) {
            size_t end = (pInit != std::string::npos && pInit > pSample) ? pInit : code.size();
            sampleText = code.substr(pSample + 7, end - (pSample + 7));
        }
    }

    auto parseBlock = [this](const std::string& text, std::vector<Instruction>& outProgram) -> bool {
        Lexer lexer(text);
        Token cur = lexer.next();

        auto match = [&](TokenType t) -> bool {
            if (cur.type == t) {
                cur = lexer.next();
                return true;
            }
            return false;
        };

        // Recursive descent expression compiler
        std::function<bool()> parseExpr;
        std::function<bool()> parseTernary;
        std::function<bool()> parseComparison;
        std::function<bool()> parseAddSub;
        std::function<bool()> parseMulDiv;
        std::function<bool()> parsePrimary;

        parsePrimary = [&]() -> bool {
            if (cur.type == TokenType::Number) {
                outProgram.push_back({OpCode::PushConst, cur.numVal});
                cur = lexer.next();
                return true;
            }
            if (cur.type == TokenType::Ident) {
                std::string name = cur.strVal;
                cur = lexer.next();
                if (cur.type == TokenType::LParen) {
                    cur = lexer.next();
                    int funcId = getFunctionId(name);
                    if (funcId < 0) {
                        lastError_ = "Unknown function: " + name;
                        return false;
                    }
                    if (cur.type != TokenType::RParen) {
                        if (!parseExpr()) return false;
                        int argCount = 1;
                        while (match(TokenType::Comma)) {
                            if (!parseExpr()) return false;
                            argCount++;
                        }
                        if (argCount != functionArity(funcId)) {
                            lastError_ = "Wrong argument count for function: " + name;
                            return false;
                        }
                    } else if (functionArity(funcId) != 0) {
                        lastError_ = "Function requires arguments: " + name;
                        return false;
                    }
                    if (!match(TokenType::RParen)) {
                        lastError_ = "Expected ')'";
                        return false;
                    }
                    outProgram.push_back({OpCode::FuncCall, 0.0, -1, -1, funcId});
                    return true;
                }
                int varIdx = getOrRegisterVar(name);
                if (varIdx < 0) {
                    lastError_ = "Too many variables: max " + std::to_string(MAX_MEMORY);
                    return false;
                }
                outProgram.push_back({OpCode::LoadVar, 0.0, varIdx});
                return true;
            }
            if (match(TokenType::LParen)) {
                if (!parseExpr()) return false;
                if (!match(TokenType::RParen)) {
                    lastError_ = "Expected ')'";
                    return false;
                }
                return true;
            }
            if (match(TokenType::Minus)) {
                if (!parsePrimary()) return false;
                outProgram.push_back({OpCode::Neg});
                return true;
            }
            lastError_ = "Unexpected token in expression";
            return false;
        };

        parseMulDiv = [&]() -> bool {
            if (!parsePrimary()) return false;
            while (cur.type == TokenType::Mul || cur.type == TokenType::Div || cur.type == TokenType::Mod) {
                TokenType op = cur.type;
                cur = lexer.next();
                if (!parsePrimary()) return false;
                if (op == TokenType::Mul) outProgram.push_back({OpCode::Mul});
                else if (op == TokenType::Div) outProgram.push_back({OpCode::Div});
                else outProgram.push_back({OpCode::Mod});
            }
            return true;
        };

        parseAddSub = [&]() -> bool {
            if (!parseMulDiv()) return false;
            while (cur.type == TokenType::Plus || cur.type == TokenType::Minus) {
                TokenType op = cur.type;
                cur = lexer.next();
                if (!parseMulDiv()) return false;
                if (op == TokenType::Plus) outProgram.push_back({OpCode::Add});
                else outProgram.push_back({OpCode::Sub});
            }
            return true;
        };

        parseComparison = [&]() -> bool {
            if (!parseAddSub()) return false;
            while (cur.type == TokenType::Eq || cur.type == TokenType::Neq ||
                   cur.type == TokenType::Lt || cur.type == TokenType::Lte ||
                   cur.type == TokenType::Gt || cur.type == TokenType::Gte) {
                TokenType op = cur.type;
                cur = lexer.next();
                if (!parseAddSub()) return false;
                if (op == TokenType::Eq) outProgram.push_back({OpCode::Eq});
                else if (op == TokenType::Neq) outProgram.push_back({OpCode::Neq});
                else if (op == TokenType::Lt) outProgram.push_back({OpCode::Lt});
                else if (op == TokenType::Lte) outProgram.push_back({OpCode::Lte});
                else if (op == TokenType::Gt) outProgram.push_back({OpCode::Gt});
                else if (op == TokenType::Gte) outProgram.push_back({OpCode::Gte});
            }
            return true;
        };

        parseTernary = [&]() -> bool {
            if (!parseComparison()) return false;
            if (match(TokenType::Question)) {
                int jmpFalseIdx = static_cast<int>(outProgram.size());
                outProgram.push_back({OpCode::JumpIfFalse, 0.0, -1, -1});
                if (!parseExpr()) return false;
                if (!match(TokenType::Colon)) {
                    lastError_ = "Expected ':' in ternary expression";
                    return false;
                }
                int jmpEndIdx = static_cast<int>(outProgram.size());
                outProgram.push_back({OpCode::Jump, 0.0, -1, -1});
                outProgram[jmpFalseIdx].targetPc = static_cast<int>(outProgram.size());
                if (!parseExpr()) return false;
                outProgram[jmpEndIdx].targetPc = static_cast<int>(outProgram.size());
            }
            return true;
        };

        parseExpr = [&]() -> bool {
            return parseTernary();
        };

        // A single statement. Shared by the top-level loop and `if` bodies so
        // assignments inside braces compile correctly (previously the if-body
        // loop advanced the lexer past an assignment without ever emitting a
        // StoreVar, silently dropping `if (c) { x = 1; }`).
        std::function<bool()> parseStatement;
        parseStatement = [&]() -> bool {
            if (match(TokenType::Semi)) return true;

            if (cur.type == TokenType::If) {
                cur = lexer.next();
                if (!match(TokenType::LParen)) { lastError_ = "Expected '(' after if"; return false; }
                if (!parseExpr()) return false;
                if (!match(TokenType::RParen)) { lastError_ = "Expected ')' after if condition"; return false; }

                int jmpFalseIdx = static_cast<int>(outProgram.size());
                outProgram.push_back({OpCode::JumpIfFalse, 0.0, -1, -1});

                if (match(TokenType::LBrace)) {
                    while (cur.type != TokenType::RBrace && cur.type != TokenType::End) {
                        if (!parseStatement()) return false;
                    }
                    if (!match(TokenType::RBrace)) { lastError_ = "Expected '}'"; return false; }
                } else {
                    // Single-statement body without braces: consume exactly one.
                    if (!parseStatement()) return false;
                }

                if (cur.type == TokenType::Else) {
                    cur = lexer.next();
                    int jmpEndIdx = static_cast<int>(outProgram.size());
                    outProgram.push_back({OpCode::Jump, 0.0, -1, -1});

                    outProgram[jmpFalseIdx].targetPc = static_cast<int>(outProgram.size());

                    if (match(TokenType::LBrace)) {
                        while (cur.type != TokenType::RBrace && cur.type != TokenType::End) {
                            if (!parseStatement()) return false;
                        }
                        if (!match(TokenType::RBrace)) { lastError_ = "Expected '}'"; return false; }
                    } else {
                        if (!parseStatement()) return false;
                    }
                    outProgram[jmpEndIdx].targetPc = static_cast<int>(outProgram.size());
                } else {
                    outProgram[jmpFalseIdx].targetPc = static_cast<int>(outProgram.size());
                }
                return true;
            }

            if (cur.type == TokenType::Ident) {
                Token peek = lexer.peek();
                if (peek.type == TokenType::Assign) {
                    std::string targetVar = cur.strVal;
                    int varIdx = getOrRegisterVar(targetVar);
                    if (varIdx < 0) {
                        lastError_ = "Too many variables: max " + std::to_string(MAX_MEMORY);
                        return false;
                    }
                    lexer.next(); // consume '='
                    cur = lexer.next(); // start of RHS expr
                    if (!parseExpr()) return false;
                    outProgram.push_back({OpCode::StoreVar, 0.0, varIdx});
                    match(TokenType::Semi);
                    return true;
                }
            }

            if (!parseExpr()) return false;
            outProgram.push_back({OpCode::Pop});
            match(TokenType::Semi);
            return true;
        };

        while (cur.type != TokenType::End) {
            if (!parseStatement()) return false;
        }

        return true;
    };

    if (!initText.empty()) {
        if (!parseBlock(initText, initBytecode_)) return false;
    }
    if (!sampleText.empty()) {
        if (!parseBlock(sampleText, sampleBytecode_)) return false;
    }

    // Bound the program so a hostile/huge script cannot make the audio-thread
    // program copy exceed the pre-reserved bytecode capacity.
    if (static_cast<int>(initBytecode_.size()) > MAX_BYTECODE ||
        static_cast<int>(sampleBytecode_.size()) > MAX_BYTECODE) {
        lastError_ = "Script too large";
        return false;
    }

    return true;
}

void LiveProg::executeBytecode(const std::vector<Instruction>& program) {
    double stack[128];
    int sp = 0;

    int pc = 0;
    const int len = static_cast<int>(program.size());

    while (pc < len) {
        const auto& instr = program[pc++];
        switch (instr.op) {
            case OpCode::PushConst:
                if (sp < 127) stack[sp++] = instr.immValue;
                break;
            case OpCode::LoadVar:
                if (sp < 127 && instr.varIndex >= 0 && instr.varIndex < static_cast<int>(memory_.size())) {
                    stack[sp++] = memory_[instr.varIndex];
                } else if (sp < 127) {
                    stack[sp++] = 0.0;
                }
                break;
            case OpCode::StoreVar:
                if (sp > 0 && instr.varIndex >= 0 && instr.varIndex < static_cast<int>(memory_.size())) {
                    memory_[instr.varIndex] = stack[--sp];
                }
                break;
            case OpCode::Add:
                if (sp >= 2) { double b = stack[--sp]; stack[sp - 1] += b; }
                break;
            case OpCode::Sub:
                if (sp >= 2) { double b = stack[--sp]; stack[sp - 1] -= b; }
                break;
            case OpCode::Mul:
                if (sp >= 2) { double b = stack[--sp]; stack[sp - 1] *= b; }
                break;
            case OpCode::Div:
                if (sp >= 2) {
                    double b = stack[--sp];
                    stack[sp - 1] = (std::abs(b) > 1e-12) ? (stack[sp - 1] / b) : 0.0;
                }
                break;
            case OpCode::Mod:
                if (sp >= 2) {
                    double b = stack[--sp];
                    stack[sp - 1] = (std::abs(b) > 1e-12) ? std::fmod(stack[sp - 1], b) : 0.0;
                }
                break;
            case OpCode::Neg:
                if (sp >= 1) stack[sp - 1] = -stack[sp - 1];
                break;
            case OpCode::Eq:
                if (sp >= 2) { double b = stack[--sp]; stack[sp - 1] = (stack[sp - 1] == b) ? 1.0 : 0.0; }
                break;
            case OpCode::Neq:
                if (sp >= 2) { double b = stack[--sp]; stack[sp - 1] = (stack[sp - 1] != b) ? 1.0 : 0.0; }
                break;
            case OpCode::Lt:
                if (sp >= 2) { double b = stack[--sp]; stack[sp - 1] = (stack[sp - 1] < b) ? 1.0 : 0.0; }
                break;
            case OpCode::Lte:
                if (sp >= 2) { double b = stack[--sp]; stack[sp - 1] = (stack[sp - 1] <= b) ? 1.0 : 0.0; }
                break;
            case OpCode::Gt:
                if (sp >= 2) { double b = stack[--sp]; stack[sp - 1] = (stack[sp - 1] > b) ? 1.0 : 0.0; }
                break;
            case OpCode::Gte:
                if (sp >= 2) { double b = stack[--sp]; stack[sp - 1] = (stack[sp - 1] >= b) ? 1.0 : 0.0; }
                break;
            case OpCode::JumpIfFalse:
                if (sp > 0) {
                    double c = stack[--sp];
                    if (c == 0.0 && instr.targetPc >= 0) pc = instr.targetPc;
                }
                break;
            case OpCode::Jump:
                if (instr.targetPc >= 0) pc = instr.targetPc;
                break;
            case OpCode::FuncCall: {
                if (sp >= 1) {
                    switch (instr.funcId) {
                        case 0: stack[sp - 1] = std::sin(stack[sp - 1]); break;
                        case 1: stack[sp - 1] = std::cos(stack[sp - 1]); break;
                        case 2: stack[sp - 1] = std::tan(stack[sp - 1]); break;
                        case 3: stack[sp - 1] = std::exp(stack[sp - 1]); break;
                        case 4: stack[sp - 1] = (stack[sp - 1] > 0.0) ? std::log(stack[sp - 1]) : 0.0; break;
                        case 5: stack[sp - 1] = (stack[sp - 1] >= 0.0) ? std::sqrt(stack[sp - 1]) : 0.0; break;
                        case 6: stack[sp - 1] = std::abs(stack[sp - 1]); break;
                        case 7: if (sp >= 2) { double b = stack[--sp]; stack[sp - 1] = std::min(stack[sp - 1], b); } break;
                        case 8: if (sp >= 2) { double b = stack[--sp]; stack[sp - 1] = std::max(stack[sp - 1], b); } break;
                        case 9: if (sp >= 2) { double b = stack[--sp]; stack[sp - 1] = std::pow(stack[sp - 1], b); } break;
                        case 10: stack[sp - 1] = std::floor(stack[sp - 1]); break;
                        case 11: stack[sp - 1] = std::ceil(stack[sp - 1]); break;
                        case 12: {
                            rngState_ ^= rngState_ << 13;
                            rngState_ ^= rngState_ >> 17;
                            rngState_ ^= rngState_ << 5;
                            stack[sp - 1] = static_cast<double>(rngState_ & 0xFFFFFFu) / 16777216.0;
                            break;
                        }
                        default: break;
                    }
                }
                break;
            }
            case OpCode::Pop:
                if (sp > 0) --sp;
                break;
        }
    }
}

void LiveProg::process(float* L, float* R, int frames) {
    if (!enabled_ || !isCompiled_ || sampleBytecode_.empty() || !L || !R || frames <= 0) return;

    for (int i = 0; i < frames; ++i) {
        memory_[idxSpl0_] = static_cast<double>(L[i]);
        memory_[idxSpl1_] = static_cast<double>(R[i]);

        executeBytecode(sampleBytecode_);

        // Sanitize the script's output: a bad script (or tan/exp/pow overflow)
        // must never inject NaN/Inf into the DAC stream, and a runaway gain is
        // bounded to a generous range so it cannot blow up the whole mix.
        double l = memory_[idxSpl0_];
        double r = memory_[idxSpl1_];
        if (!std::isfinite(l)) l = 0.0;
        if (!std::isfinite(r)) r = 0.0;
        L[i] = static_cast<float>(std::clamp(l, -4.0, 4.0));
        R[i] = static_cast<float>(std::clamp(r, -4.0, 4.0));
    }
}

void LiveProg::processInterleaved(float* buffer, int frames, int channels) {
    if (!enabled_ || !isCompiled_ || sampleBytecode_.empty() || !buffer || frames <= 0 || channels < 2) return;

    for (int i = 0; i < frames; ++i) {
        memory_[idxSpl0_] = static_cast<double>(buffer[i * channels]);
        memory_[idxSpl1_] = static_cast<double>(buffer[i * channels + 1]);

        executeBytecode(sampleBytecode_);

        double l = memory_[idxSpl0_];
        double r = memory_[idxSpl1_];
        if (!std::isfinite(l)) l = 0.0;
        if (!std::isfinite(r)) r = 0.0;
        buffer[i * channels] = static_cast<float>(std::clamp(l, -4.0, 4.0));
        buffer[i * channels + 1] = static_cast<float>(std::clamp(r, -4.0, 4.0));
    }
}
