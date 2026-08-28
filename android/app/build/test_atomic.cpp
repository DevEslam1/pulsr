#include <memory>
#include <atomic>
#include <iostream>
#include <cassert>

template<typename T>
class AtomicSharedPtr {
public:
    AtomicSharedPtr() = default;
    explicit AtomicSharedPtr(std::shared_ptr<T> p) : ptr_(std::move(p)) {}
    std::shared_ptr<T> load(std::memory_order order = std::memory_order_seq_cst) const noexcept {
        return std::atomic_load_explicit(&ptr_, order);
    }
    void store(std::shared_ptr<T> desired, std::memory_order order = std::memory_order_seq_cst) noexcept {
        std::atomic_store_explicit(&ptr_, std::move(desired), order);
    }
private:
    std::shared_ptr<T> ptr_;
};

struct Foo { int x = 42; };

int main() {
    AtomicSharedPtr<const Foo> a(std::make_shared<Foo>());
    auto p = a.load();
    assert(p && p->x == 42);
    a.store(std::make_shared<Foo>());
    auto p2 = a.load();
    assert(p2 && p2->x == 42);
    std::cout << "AtomicSharedPtr test passed!" << std::endl;
    return 0;
}
