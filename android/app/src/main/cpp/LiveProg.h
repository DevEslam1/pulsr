// android/app/src/main/cpp/LiveProg.h
#pragma once

#include "DspParams.h"
#include <string>
#include <vector>
#include <unordered_map>
#include <memory>

class LiveProg {
public:
    LiveProg();
    void setSampleRate(double sampleRate);
    void setEnabled(bool enabled) { enabled_ = enabled; }
    bool isEnabled() const { return enabled_; }
    void applyParams(const LiveProgParamSet& params);
    void reset();

    bool loadCode(const std::string& scriptCode);
    const std::string& getLoadedCode() const { return loadedCode_; }
    const std::string& getLastError() const { return lastError_; }
    bool isCompiled() const { return isCompiled_; }

    /// Packages the current compiled bytecode + variable layout into a neutral,
    /// immutable program that can be published through the snapshot and applied
    /// on the audio thread without compiling/allocating. Call on the control
    /// thread after loadCode().
    std::shared_ptr<const LiveProgProgram> buildProgram() const;

    void setSlider(int index, double value); // index: 1..8
    double getSlider(int index) const;

    void process(float* L, float* R, int frames);
    void processInterleaved(float* buffer, int frames, int channels = 2);

private:
    enum class OpCode {
        PushConst,
        LoadVar,
        StoreVar,
        Add,
        Sub,
        Mul,
        Div,
        Mod,
        Neg,
        Eq,
        Neq,
        Lt,
        Lte,
        Gt,
        Gte,
        JumpIfFalse,
        Jump,
        FuncCall,
        Pop
    };

    struct Instruction {
        OpCode op;
        double immValue = 0.0;
        int varIndex = -1;
        int targetPc = -1;
        int funcId = -1;
    };

    double sampleRate_ = 48000.0;
    bool enabled_ = false;
    bool isCompiled_ = false;
    std::string loadedCode_;
    std::string lastError_;

    // Variables table: indices mapped to names
    std::unordered_map<std::string, int> varMap_;
    std::vector<double> memory_;

    // Special variable indices
    int idxSpl0_ = -1;
    int idxSpl1_ = -1;
    int idxSrate_ = -1;
    int idxSliders_[8] = {-1, -1, -1, -1, -1, -1, -1, -1};

    // Bytecode programs
    std::vector<Instruction> initBytecode_;
    std::vector<Instruction> sampleBytecode_;

    int getOrRegisterVar(const std::string& name);
    bool compileScript(const std::string& code);
    void executeBytecode(const std::vector<Instruction>& program);
    void applyPreparedProgram(const std::shared_ptr<const LiveProgProgram>& program);

    static constexpr int MAX_BYTECODE = 8192;
    static constexpr int MAX_MEMORY = 2048;

    // Identity of the last published prepared program, for change detection.
    std::shared_ptr<const LiveProgProgram> activeProgram_;

    // Real-time xorshift PRNG state for the rand() builtin (std::rand() is a
    // global, non-reentrant libc call that is not safe in the audio callback).
    uint32_t rngState_ = 0x12345678u;
};
